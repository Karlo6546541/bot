"""Strategija: čista funkcija (stanje tržišta, inventar) -> nalozi.

Bez predviđanja smjera. Tri izvora profita, redom prioriteta:

1. COMPLETE-SET ARB  : ask_up_eff + ask_down_eff < 1 - margin  -> kupi oba, profit zaključan odmah.
2. LOCK              : imamo višak jedne strane; kupi drugu stranu ako
                       avg_cost(višak) + ask_eff(druga) <= 1 - margin -> parovi isplaćuju točno 1.
3. LATENCY EDGE      : Binance se pomaknuo, Polymarket knjiga još stoji (kasni 1-2 s).
                       Uzmi zastarjelu ponudu ako je fer q - a_eff > prag I ako je edge
                       objašnjen nedavnim pomakom Binancea (štiti od grešaka modela).
                       Isto i za prodaju zastarjelih bidova.

Kroz prozor bot tipično pokupi jeftin UP na skoku, pa jeftin DOWN na padu ->
par UP+DOWN košta < 1, a isplaćuje 1. Pojedinačne "oklade" pobjeđuju ~50%,
ali svaka je kupljena ispod fer vrijednosti, a parovi su bez rizika.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from .config import Config
from .mathcore import (
    eff_buy,
    eff_sell,
    mv_target_shares,
    prob_density,
    prob_up,
    taker_fee_per_share,
)

UP, DOWN = "UP", "DOWN"
BUY, SELL = "BUY", "SELL"


def other(side: str) -> str:
    return DOWN if side == UP else UP


@dataclass
class Book:
    bids: list[tuple[float, float]] = field(default_factory=list)  # silazno po cijeni
    asks: list[tuple[float, float]] = field(default_factory=list)  # uzlazno po cijeni
    ts: float = 0.0

    @property
    def best_bid(self) -> float | None:
        return self.bids[0][0] if self.bids else None

    @property
    def best_ask(self) -> float | None:
        return self.asks[0][0] if self.asks else None


@dataclass
class MarketView:
    t_now: float
    t_start: float
    t_end: float
    strike: float
    spot: float               # Binance mid sada
    spot_lookback: float      # Binance mid prije lookback_sec
    basis: float              # EWMA ln(Chainlink/Binance)
    basis_std: float
    sigma_sec: float
    up: Book
    down: Book

    def book(self, side: str) -> Book:
        return self.up if side == UP else self.down


@dataclass
class Fair:
    q: float          # P(UP)
    sigma_q: float    # nesigurnost q
    dq: float         # promjena q implicirana pomakom Binancea u lookback prozoru
    density: float
    d: float


@dataclass
class Order:
    side: str
    action: str
    price: float      # limit cijena (najgori nivo)
    shares: float
    reason: str
    edge: float = 0.0

    @property
    def notional(self) -> float:
        return self.price * self.shares


@dataclass
class Inventory:
    n_up: float = 0.0
    n_down: float = 0.0
    cost_up: float = 0.0      # cost basis uključujući fee
    cost_down: float = 0.0
    cash: float = 0.0         # neto novčani tok (negativno = potrošeno)
    fees: float = 0.0
    spent: float = 0.0        # bruto potrošeno na kupnje (za budžet)
    n_trades: int = 0

    def n(self, side: str) -> float:
        return self.n_up if side == UP else self.n_down

    def avg_cost(self, side: str) -> float:
        n = self.n(side)
        if n <= 0:
            return 0.0
        return (self.cost_up if side == UP else self.cost_down) / n

    def imbalance(self, side: str) -> float:
        return self.n(side) - self.n(other(side))

    def apply_fill(self, side: str, action: str, shares: float, price: float, fee: float) -> None:
        if shares <= 0:
            return
        self.n_trades += 1
        self.fees += fee
        if action == BUY:
            c = shares * price + fee
            self.cash -= c
            self.spent += c
            if side == UP:
                self.n_up += shares
                self.cost_up += c
            else:
                self.n_down += shares
                self.cost_down += c
        else:
            self.cash += shares * price - fee
            n = self.n(side)
            frac = min(shares / n, 1.0) if n > 0 else 0.0
            if side == UP:
                self.cost_up *= 1 - frac
                self.n_up -= shares
            else:
                self.cost_down *= 1 - frac
                self.n_down -= shares

    def worst_case_pnl(self) -> float:
        return self.cash + min(self.n_up, self.n_down)

    def locked_pnl(self) -> float:
        return max(self.worst_case_pnl(), 0.0)

    def expected_pnl(self, q: float) -> float:
        return self.cash + q * self.n_up + (1 - q) * self.n_down

    def settle(self, up_won: bool) -> float:
        return self.cash + (self.n_up if up_won else self.n_down)


class Strategy:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    # ------------------------------------------------------------ fer vrijednost
    def fair(self, v: MarketView) -> Fair:
        c = self.cfg
        tau = max(v.t_end - v.t_now, 1e-3)
        s_eff = v.spot * math.exp(v.basis)
        q = prob_up(s_eff, v.strike, v.sigma_sec, tau, c.t_dof)
        dens, d = prob_density(s_eff, v.strike, v.sigma_sec, tau, c.t_dof)
        # Nesigurnost: (1) greška baze -> greška spota; (2) greška sigme.
        # dq/dsigma = -pdf(d) * d / sigma  =>  |dq| ~ pdf(d)|d| * rel_err
        pdf_d = dens * v.sigma_sec * math.sqrt(tau)
        sq = math.hypot(dens * v.basis_std, pdf_d * abs(d) * c.vol_rel_err)
        r_l = math.log(v.spot / v.spot_lookback) if v.spot_lookback > 0 else 0.0
        return Fair(q=q, sigma_q=sq, dq=dens * r_l, density=dens, d=d)

    # ------------------------------------------------------------ odluka
    def decide(self, v: MarketView, inv: Inventory) -> list[Order]:
        c = self.cfg
        tau = v.t_end - v.t_now
        if v.t_now - v.t_start < c.start_delay_sec or tau < c.stop_before_end_sec:
            return []
        f = self.fair(v)
        budget = c.max_window_usd - inv.spent
        if budget <= c.min_shares * c.min_price:
            return []

        arb = self._complete_set(v, budget)
        if arb:
            return arb

        orders: list[Order] = []
        for side in (UP, DOWN):
            o = self._buy_side(side, v, f, inv, budget)
            if o:
                orders.append(o)
                budget -= o.notional
            o = self._sell_side(side, v, f, inv)
            if o:
                orders.append(o)
        return orders

    # ------------------------------------------------------------ 1) complete set
    def _complete_set(self, v: MarketView, budget: float) -> list[Order]:
        c = self.cfg
        ua, da = v.up.asks, v.down.asks
        i = j = 0
        rem_u = ua[0][1] if ua else 0.0
        rem_d = da[0][1] if da else 0.0
        shares = 0.0
        worst_u = worst_d = 0.0
        spend = 0.0
        while i < len(ua) and j < len(da):
            pu, pd = ua[i][0], da[j][0]
            pair = eff_buy(pu, c.fee_rate, c.fee_exp) + eff_buy(pd, c.fee_rate, c.fee_exp)
            if pair > 1.0 - c.lock_margin:
                break
            take = min(rem_u, rem_d, (budget - spend) / (pu + pd))
            if take <= 0:
                break
            shares += take
            spend += take * (pu + pd)
            worst_u, worst_d = pu, pd
            rem_u -= take
            rem_d -= take
            if rem_u <= 1e-9:
                i += 1
                rem_u = ua[i][1] if i < len(ua) else 0.0
            if rem_d <= 1e-9:
                j += 1
                rem_d = da[j][1] if j < len(da) else 0.0
        shares = min(shares, c.max_order_usd / max(worst_u + worst_d, 1e-9))
        shares = math.floor(shares * 100) / 100
        if shares < c.min_shares:
            return []
        edge = 1.0 - eff_buy(worst_u, c.fee_rate, c.fee_exp) - eff_buy(worst_d, c.fee_rate, c.fee_exp)
        return [
            Order(UP, BUY, worst_u, shares, "COMPLETE_SET", edge),
            Order(DOWN, BUY, worst_d, shares, "COMPLETE_SET", edge),
        ]

    # ------------------------------------------------------------ 2) + 3) kupnja
    def _buy_side(self, side: str, v: MarketView, f: Fair, inv: Inventory, budget: float) -> Order | None:
        c = self.cfg
        book = v.book(side)
        q_s = f.q if side == UP else 1.0 - f.q
        dq_s = f.dq if side == UP else -f.dq
        thr = c.min_edge + c.z_uncert * f.sigma_q
        explained = max(dq_s, 0.0) * c.explain_mult + c.unexplained_slack
        R = c.risk_tolerance_usd

        excess_other = inv.n(other(side)) - inv.n(side)
        avg_other = inv.avg_cost(other(side))
        imb = inv.imbalance(side)

        taken = 0.0
        notional = 0.0
        worst = None
        reason = None
        best_edge = None
        cap_usd = min(c.max_order_usd, budget)

        for p, size in book.asks:
            if p > c.max_price or p < c.min_price:
                break
            a_eff = eff_buy(p, c.fee_rate, c.fee_exp)
            edge = q_s - a_eff
            want = 0.0
            # (2) LOCK: upari višak suprotne strane uz zaključani profit
            lock_room = excess_other - taken
            if lock_room > 0 and avg_other + a_eff <= 1.0 - c.lock_margin:
                want = lock_room
                reason = reason or "LOCK"
            # (3) LATENCY EDGE: zastarjela ponuda, edge objašnjen pomakom Binancea
            if thr <= edge <= explained:
                mv = mv_target_shares(q_s, a_eff, imb + taken, R)
                if mv > want:
                    want = mv
                    reason = "LATENCY" if reason != "LOCK" else "LOCK+LATENCY"
            if want <= 0:
                break
            take = min(size, want, (cap_usd - notional) / p)
            if take <= 0:
                break
            taken += take
            notional += take * p
            worst = p
            best_edge = edge if best_edge is None else best_edge
            if take < size:
                break

        taken = math.floor(taken * 100) / 100
        if worst is not None and taken < c.min_shares:
            taken = self._round_up(taken, book.asks, worst, cap_usd, buy=True)
        if worst is None or taken < c.min_shares:
            return None
        return Order(side, BUY, worst, taken, reason or "?", best_edge or 0.0)

    def _round_up(self, taken: float, levels, worst: float, cap_usd: float, buy: bool, held: float = 0.0) -> float:
        """Mali bankroll: Kelly često da < 5 dionica (Polymarket minimum). Ako je željena
        količina barem round_up_frac * min_shares, a knjiga i limit to dopuštaju, uzmi minimum."""
        c = self.cfg
        if taken < c.round_up_frac * c.min_shares:
            return taken
        depth = sum(s for p, s in levels if (p <= worst + 1e-9 if buy else p >= worst - 1e-9))
        if depth < c.min_shares or c.min_shares * worst > cap_usd + 1e-9:
            return taken
        if not buy and held < c.min_shares:
            return taken
        return c.min_shares

    # ------------------------------------------------------------ 3b) prodaja zastarjelih bidova
    def _sell_side(self, side: str, v: MarketView, f: Fair, inv: Inventory) -> Order | None:
        c = self.cfg
        held = inv.n(side)
        if held < c.min_shares:
            return None
        book = v.book(side)
        q_s = f.q if side == UP else 1.0 - f.q
        dq_s = f.dq if side == UP else -f.dq
        thr = c.min_edge + c.z_uncert * f.sigma_q
        explained = max(-dq_s, 0.0) * c.explain_mult + c.unexplained_slack
        R = c.risk_tolerance_usd
        imb = inv.imbalance(side)

        sold = 0.0
        worst = None
        best_edge = None
        for p, size in book.bids:
            if p < c.min_price:
                break
            b_eff = eff_sell(p, c.fee_rate, c.fee_exp)
            edge = b_eff - q_s
            if not (thr <= edge <= explained):
                break
            target = -mv_target_shares(q_s, b_eff, imb - sold, R)  # koliko želimo prodati
            want = min(target, held - sold)
            if want <= 0:
                break
            take = min(size, want, c.max_order_usd / p)
            sold += take
            worst = p
            best_edge = edge if best_edge is None else best_edge
            if take < size:
                break
        sold = math.floor(sold * 100) / 100
        if worst is not None and sold < c.min_shares:
            sold = self._round_up(sold, book.bids, worst, c.max_order_usd, buy=False, held=held)
        if worst is None or sold < c.min_shares:
            return None
        return Order(side, SELL, worst, sold, "STALE_BID", best_edge or 0.0)


def fee_for(cfg: Config, price: float, shares: float) -> float:
    return shares * taker_fee_per_share(price, cfg.fee_rate, cfg.fee_exp)
