"""Pokretanje:  python main.py            (paper)
               python main.py --live     (pravi novac, treba POLY_PRIVATE_KEY)"""
import argparse
import asyncio
import logging

from polybot.bot import Bot
from polybot.config import Config


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true", help="šalji prave naloge (default: paper)")
    ap.add_argument("--bankroll", type=float)
    ap.add_argument("--max-window-usd", type=float)
    ap.add_argument("--min-edge", type=float)
    ap.add_argument("--binance-ws", type=str, help="npr. wss://stream.binance.us:9443/ws/btcusdt@bookTicker")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    cfg = Config.from_env()
    if a.live:
        cfg.live = True
    if a.bankroll:
        cfg.bankroll_usd = a.bankroll
    if a.max_window_usd:
        cfg.max_window_usd = a.max_window_usd
    if a.min_edge is not None:
        cfg.min_edge = a.min_edge
    if a.binance_ws:
        cfg.binance_ws = a.binance_ws

    logging.basicConfig(level=logging.DEBUG if a.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("websockets").setLevel(logging.WARNING)
    logging.info("mode=%s bankroll=%.0f R=%.0f max_window=%.0f", "LIVE" if cfg.live else "PAPER",
                 cfg.bankroll_usd, cfg.risk_tolerance_usd, cfg.max_window_usd)
    asyncio.run(Bot(cfg).run())


if __name__ == "__main__":
    main()
