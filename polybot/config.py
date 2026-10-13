"""Konfiguracija bota. Sve vrijednosti se mogu pregaziti env varijablama
(npr. POLYBOT_MIN_EDGE=0.02) ili CLI argumentima u main.py."""
from __future__ import annotations

import os
from dataclasses import dataclass, fields


@dataclass
class Config:
    # --- način rada ---
    live: bool = False                  # False = paper trading (default!)
    bankroll_usd: float = 500.0

    # --- 5-min prozori ---
    window_sec: int = 300
    start_delay_sec: float = 3.0        # ne trguj prvih N s (strike se još potvrđuje)
    stop_before_end_sec: float = 15.0   # ne trguj zadnjih N s (Chainlink vs Binance šum dominira)

    # --- Polymarket taker fee: fee = shares * rate * (p(1-p))^exp ---
    fee_rate: float = 0.25
    fee_exp: float = 2.0

    # --- model fer vjerojatnosti ---
    sigma_prior_annual: float = 0.50    # početna volatilnost dok EWMA ne skupi podatke
    vol_halflife_sec: float = 300.0
    vol_sample_sec: float = 1.0
    t_dof: float = 4.0                  # Student-t stupnjevi slobode (debeli repovi); 0 = normalna
    vol_rel_err: float = 0.20           # relativna nesigurnost procjene sigme
    basis_halflife_sec: float = 60.0    # EWMA baze Chainlink/Binance
    lookback_sec: float = 2.0           # prozor za mjerenje "svježeg" pomaka Binancea (latencija)

    # --- pragovi edgea ---
    min_edge: float = 0.015             # min. (fer - efektivna cijena) po dionici
    z_uncert: float = 1.0               # koliko sigma nesigurnosti modela tražimo povrh min_edge
    explain_mult: float = 1.5           # edge mora biti objašnjen nedavnim pomakom Binancea
    unexplained_slack: float = 0.01
    lock_margin: float = 0.01           # min. zaključani profit po paru UP+DOWN

    # --- veličina pozicije ---
    kelly_mult: float = 0.5             # R = kelly_mult * bankroll (frakcijski Kelly)
    max_order_usd: float = 50.0
    max_window_usd: float = 200.0
    min_shares: float = 5.0
    side_cooldown_sec: float = 0.5
    min_price: float = 0.03
    max_price: float = 0.97

    # --- petlja / paper ---
    loop_ms: float = 50.0
    paper_latency_ms: float = 250.0     # simulirano kašnjenje izvršenja u paper modu
    settle_delay_sec: float = 10.0

    # --- endpointi ---
    binance_ws: str = "wss://stream.binance.com:9443/ws/btcusdt@bookTicker"
    rtds_ws: str = "wss://ws-live-data.polymarket.com"
    clob_ws: str = "wss://ws-subscriptions-clob.polymarket.com/ws/market"
    clob_host: str = "https://clob.polymarket.com"
    gamma_host: str = "https://gamma-api.polymarket.com"
    slug_prefix: str = "btc-updown-5m-"

    # --- logovi ---
    log_dir: str = "logs"

    @property
    def risk_tolerance_usd(self) -> float:
        return self.kelly_mult * self.bankroll_usd

    @classmethod
    def from_env(cls) -> "Config":
        cfg = cls()
        for f in fields(cls):
            raw = os.environ.get("POLYBOT_" + f.name.upper())
            if raw is None:
                continue
            cur = getattr(cfg, f.name)
            if isinstance(cur, bool):
                val = raw.strip().lower() in ("1", "true", "yes", "on")
            elif isinstance(cur, int):
                val = int(raw)
            elif isinstance(cur, float):
                val = float(raw)
            else:
                val = raw
            setattr(cfg, f.name, val)
        return cfg
