"""Monte-Carlo simulator: provjerava matematiku strategije offline.

Model svijeta:
  * BTC: log-random-walk s Student-t (nu=4) šokovima (debeli repovi), dt = 0.1 s
  * Binance = prava cijena u realnom vremenu (bot ga vidi odmah)
  * Polymarket market maker kotira fer vrijednost izračunatu iz cijene stare `mm_lag` s,
    osvježava kotacije svakih `mm_requote` s, spread +-half_spread, 3 nivoa dubine,
    plus vlastiti šum u procjeni (AR(1))
  * Bot izvršava s kašnjenjem `exec_latency`; s vjerojatnošću `competitor_prob`
    netko drugi je već pokupio zastarjelu likvidnost (nalog promaši)
  * Fee: Polymarket crypto taker fee 0.25*(p(1-p))^2 po dionici

Primjer:  python simulate.py --windows 300 --mm-lag 1.5
"""
from __future__ import annotations

import argparse
import math
import random
import statistics
from dataclasses import replace

from polybot.config import Config
from polybot.execution import match_against_book
from polybot.mathcore import EwmaVol, annual_to_sec_sigma, prob_up
from polybot.strategy import BUY, DOWN, UP, Book, Inventory, MarketView, Strategy


def t_shock(rng: random.Random, nu: float) -> float:
    if nu <= 2:
        return rng.gauss(0, 1)
    chi2 = rng.gammavariate(nu / 2, 2)
    return rng.gauss(0, 1) / math.sqrt(chi2 / nu) * math.sqrt((nu - 2) / nu)


def make_books(q_mm: float, half_spread: float, rng: random.Random) -> tuple[Book, Book]:
    q_mm = min(max(q_mm, 0.02), 0.98)
    bid = math.floor((q_mm - half_spread) * 100) / 100
    ask = math.ceil((q_mm + half_spread) * 100) / 100
    bid = max(bid, 0.01)
    ask = min(ask, 0.99)
    up_bids = [(round(bid - 0.01 * i, 2), rng.uniform(30, 250)) for i in range(3) if bid - 0.01 * i >= 0.01]
    up_asks = [(round(ask + 0.01 * i, 2), rng.uniform(30, 250)) for i in range(3) if ask + 0.01 * i <= 0.99]
    # DOWN knjiga je komplement UP knjige (Polymarket spaja ih kroz complete-set mint/merge)
    dn_asks = [(round(1 - p, 2), s) for p, s in up_bids]
    dn_bids = [(round(1 - p, 2), s) for p, s in up_asks]
    return Book(up_bids, up_asks), Book(dn_bids, dn_asks)


def run_window(cfg: Config, rng: random.Random, a, path: list[float] | None = None,
               warmup: list[float] | None = None) -> dict:
    """path: cijene na mreži od 0.1 s (n+1 točaka). Ako None, generira se sintetički put.
    warmup: 1-s cijene prije prozora za zagrijavanje estimatora volatilnosti."""
    dt = 0.1
    T = cfg.window_sec
    n = int(T / dt)
    sig = annual_to_sec_sigma(a.sigma)
    real = path is not None
    if not real:
        # cijeli put unaprijed (MM-u treba prošlost, botu sadašnjost)
        S0 = 60000.0 * math.exp(rng.gauss(0, 0.05))
        path = [S0]
        for _ in range(n):
            path.append(path[-1] * math.exp(sig * math.sqrt(dt) * t_shock(rng, 4.0)))
    strike = path[0]
    strat = Strategy(cfg)
    inv = Inventory()
    vol = EwmaVol(annual_to_sec_sigma(cfg.sigma_prior_annual), cfg.vol_halflife_sec, cfg.vol_sample_sec)
    # zagrij estimator volatilnosti s 10 min "prošlosti"
    if warmup:
        for k, p in enumerate(warmup):
            vol.update(p, -len(warmup) + k)
    else:
        p = path[0]
        for k in range(600):
            p *= math.exp(sig * t_shock(rng, 4.0))
            vol.update(p, -600 + k)

    lag_steps = int(round(a.mm_lag / dt))
    requote_steps = max(int(round(a.mm_requote / dt)), 1)
    lat_steps = max(int(round(a.exec_latency / dt)), 1)
    lb_steps = int(round(cfg.lookback_sec / dt))
    mm_noise = 0.0
    up_book = dn_book = Book()
    pending: list[tuple[int, object]] = []
    last_fire = {UP: -1e9, DOWN: -1e9}
    legs = []  # (side, shares)

    for i in range(n + 1):
        t = i * dt
        tau = T - t
        if i % requote_steps == 0:
            ref = path[max(i - lag_steps, 0)]
            mm_noise = 0.8 * mm_noise + rng.gauss(0, a.mm_noise)
            mm_sig = vol.sigma if real else sig   # na pravim podacima MM ne zna "pravu" sigmu
            q_mm = prob_up(ref, strike, mm_sig, max(tau, 1e-3), 4.0) + mm_noise
            up_book, dn_book = make_books(q_mm, a.half_spread, rng)
        vol.update(path[i], t)

        # izvrši naloge kojima je isteklo kašnjenje (na knjizi koja je TADA aktualna)
        still = []
        for due, o in pending:
            if due > i:
                still.append((due, o))
                continue
            if rng.random() < a.competitor_prob:
                continue
            fl = match_against_book(up_book if o.side == UP else dn_book, o, cfg)
            if fl.shares > 0:
                inv.apply_fill(o.side, o.action, fl.shares, fl.avg_price, fl.fee)
                legs.append((o.side, fl.shares if o.action == BUY else -fl.shares))
        pending = still
        if pending:
            continue

        v = MarketView(
            t_now=t, t_start=0.0, t_end=T, strike=strike,
            spot=path[i], spot_lookback=path[max(i - lb_steps, 0)],
            basis=0.0, basis_std=a.basis_err, sigma_sec=vol.sigma,
            up=up_book, down=dn_book,
        )
        for o in strat.decide(v, inv):
            if o.reason != "COMPLETE_SET" and t - last_fire[o.side] < cfg.side_cooldown_sec:
                continue
            last_fire[o.side] = t
            pending.append((i + lat_steps, o))

    up_won = path[-1] >= strike
    pnl = inv.settle(up_won)
    leg_wins = sum(1 for s, sh in legs if sh > 0 and (s == UP) == up_won)
    leg_buys = sum(1 for _, sh in legs if sh > 0)
    return dict(pnl=pnl, up_won=up_won, strike=strike, close=path[-1], n_up=inv.n_up, n_down=inv.n_down,
                n_trades=inv.n_trades, worst=inv.worst_case_pnl(), fees=inv.fees, spent=inv.spent, traded=inv.n_trades > 0,
                locked=inv.worst_case_pnl() > 0, leg_wins=leg_wins, leg_buys=leg_buys,
                hedged=min(inv.n_up, inv.n_down), gross=max(inv.n_up, inv.n_down))


def add_world_args(ap: argparse.ArgumentParser) -> None:
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--sigma", type=float, default=0.55, help="godišnja volatilnost BTC")
    ap.add_argument("--mm-lag", type=float, default=1.5, help="kašnjenje Polymarket MM-a (s)")
    ap.add_argument("--mm-requote", type=float, default=0.5)
    ap.add_argument("--mm-noise", type=float, default=0.0)
    ap.add_argument("--half-spread", type=float, default=0.01)
    ap.add_argument("--exec-latency", type=float, default=0.25)
    ap.add_argument("--competitor-prob", type=float, default=0.3)
    ap.add_argument("--basis-err", type=float, default=2e-5)
    ap.add_argument("--no-fee", action="store_true")
    ap.add_argument("--bankroll", type=float, help="skaliraj limite na bankroll (npr. 50)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows", type=int, default=200)
    add_world_args(ap)
    a = ap.parse_args()

    cfg = Config()
    if a.bankroll:
        cfg.apply_bankroll(a.bankroll)
    if a.no_fee:
        cfg = replace(cfg, fee_rate=0.0)
    rng = random.Random(a.seed)
    res = [run_window(cfg, rng, a) for _ in range(a.windows)]
    traded = [r for r in res if r["traded"]]
    pnls = [r["pnl"] for r in res]
    tp = [r["pnl"] for r in traded]
    lw = sum(r["leg_wins"] for r in res)
    lb = sum(r["leg_buys"] for r in res)
    sd = statistics.pstdev(pnls) if len(pnls) > 1 else 0.0
    print(f"windows={len(res)}  traded={len(traded)}  mm_lag={a.mm_lag}s  exec_lat={a.exec_latency}s  "
          f"competitor={a.competitor_prob:.0%}  fee={'off' if a.no_fee else 'on'}")
    print(f"total PnL           : {sum(pnls):10.2f} $")
    print(f"mean PnL / window   : {statistics.mean(pnls):10.3f} $   (std {sd:.2f}, Sharpe/window {statistics.mean(pnls) / sd if sd else 0:.3f})")
    if traded:
        print(f"profitable windows  : {100 * sum(p > 0 for p in tp) / len(tp):9.1f} %  (of traded)")
        print(f"locked windows      : {100 * sum(r['locked'] for r in traded) / len(traded):9.1f} %  (worst case > 0)")
        print(f"hedged share ratio  : {100 * sum(r['hedged'] for r in traded) / max(sum(r['gross'] for r in traded), 1e-9):9.1f} %")
    print(f"leg win rate        : {100 * lw / max(lb, 1):9.1f} %  ({lb} buy legs)  <- 'pogodak smjera' po nalogu")
    print(f"fees paid           : {sum(r['fees'] for r in res):10.2f} $   spent {sum(r['spent'] for r in res):.0f} $")


if __name__ == "__main__":
    main()
