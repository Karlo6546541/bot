"""Glavna petlja: za svaki 5-min prozor pronađi tržište, uhvati strike, trguj, obračunaj."""
from __future__ import annotations

import asyncio
import csv
import logging
import math
import os
import time

import aiohttp

from .config import Config
from .execution import LiveBroker, PaperBroker
from .feeds import BinanceFeed, BookFeed, ChainlinkFeed
from .market import WindowMarket, find_window
from .strategy import BUY, DOWN, UP, Inventory, MarketView, Strategy

log = logging.getLogger("polybot")


class CsvLog:
    def __init__(self, path: str, header: list[str]):
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        new = not os.path.exists(path)
        self.f = open(path, "a", newline="")
        self.w = csv.writer(self.f)
        if new:
            self.w.writerow(header)
            self.f.flush()

    def row(self, *vals):
        self.w.writerow(vals)
        self.f.flush()


class Bot:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.strategy = Strategy(cfg)
        self.binance = BinanceFeed(cfg)
        self.chainlink = ChainlinkFeed(cfg, self.binance)
        self.live_broker = LiveBroker(cfg) if cfg.live else None
        self.trades = CsvLog(os.path.join(cfg.log_dir, "trades.csv"),
                             ["ts", "slug", "side", "action", "reason", "limit", "shares", "avg_px", "fee", "edge", "q", "tau"])
        self.windows = CsvLog(os.path.join(cfg.log_dir, "windows.csv"),
                              ["slug", "strike", "close", "up_won", "n_up", "n_down", "spent", "fees", "pnl", "locked_pnl"])
        self.total_pnl = 0.0
        self.n_windows = 0
        self.n_win_windows = 0

    async def run(self):
        tasks = [asyncio.create_task(self.binance.run()), asyncio.create_task(self.chainlink.run())]
        async with aiohttp.ClientSession(trust_env=True) as session:
            try:
                while True:
                    if self.cfg.max_loss_usd > 0 and self.total_pnl <= -self.cfg.max_loss_usd:
                        log.error("STOP-LOSS: PnL %.2f <= -%.2f, bot se zaustavlja", self.total_pnl,
                                  self.cfg.max_loss_usd)
                        return
                    now = time.time()
                    t0 = int(now // self.cfg.window_sec) * self.cfg.window_sec
                    if now > t0 + self.cfg.window_sec - self.cfg.stop_before_end_sec - 5:
                        t0 += self.cfg.window_sec          # premalo vremena, čekaj sljedeći
                    wm = await find_window(self.cfg, session, t0)
                    if not wm:
                        log.warning("market for %s not found, skipping", t0)
                        await asyncio.sleep(max(t0 + self.cfg.window_sec - time.time(), 1))
                        continue
                    await self.trade_window(wm)
            finally:
                for t in tasks:
                    t.cancel()

    async def _strike(self, wm: WindowMarket) -> float | None:
        if wm.price_to_beat:
            return wm.price_to_beat
        wait = max(wm.t_start - time.time(), 0) + 5
        p = await self.chainlink.wait_price_at(wm.t_start, wait)
        if p:
            return p
        bn = self.binance.hist.at(wm.t_start)
        return bn * math.exp(self.chainlink.basis.mean) if bn else None

    async def trade_window(self, wm: WindowMarket):
        cfg = self.cfg
        log.info("=== window %s  (%s -> %s)", wm.slug, wm.t_start, wm.t_end)
        tokens = {UP: wm.token_up, DOWN: wm.token_down}
        books = BookFeed(cfg, tokens)
        book_task = asyncio.create_task(books.run())
        inv = Inventory()
        broker = self.live_broker or PaperBroker(cfg, lambda s: books.books[s])
        last_fire = {UP: 0.0, DOWN: 0.0}
        try:
            if time.time() < wm.t_start:
                await asyncio.sleep(wm.t_start - time.time())
            strike = await self._strike(wm)
            if not strike:
                log.warning("no strike for %s, skipping", wm.slug)
                return
            try:
                await asyncio.wait_for(books.ready.wait(), timeout=10)
            except asyncio.TimeoutError:
                log.warning("book not ready for %s", wm.slug)
                return
            log.info("strike=%.2f  sigma_ann=%.1f%%  basis=%.2fbp", strike,
                     self.binance.vol.sigma * math.sqrt(365 * 86400) * 100, self.chainlink.basis.mean * 1e4)

            while time.time() < wm.t_end - cfg.stop_before_end_sec:
                await asyncio.sleep(cfg.loop_ms / 1000.0)
                now = time.time()
                spot = self.binance.hist.last
                spot_lb = self.binance.hist.at(now - cfg.lookback_sec)
                if not spot or not spot_lb or now - self.binance.hist.last_t > 2.0:
                    continue  # Binance feed zastario -> ne trguj
                v = MarketView(
                    t_now=now, t_start=wm.t_start, t_end=wm.t_end, strike=strike,
                    spot=spot, spot_lookback=spot_lb,
                    basis=self.chainlink.basis.mean, basis_std=max(self.chainlink.basis.std, 1e-5),
                    sigma_sec=self.binance.vol.sigma,
                    up=books.books[UP], down=books.books[DOWN],
                )
                orders = self.strategy.decide(v, inv)
                if not orders:
                    continue
                fair = self.strategy.fair(v)
                is_pair = all(o.reason == "COMPLETE_SET" for o in orders)
                todo = [o for o in orders if is_pair or now - last_fire[o.side] >= cfg.side_cooldown_sec]
                if not todo:
                    continue
                fills = await asyncio.gather(*(broker.execute(o, tokens[o.side]) for o in todo))
                for o, fl in zip(todo, fills):
                    last_fire[o.side] = now
                    if fl.shares <= 0:
                        continue
                    inv.apply_fill(o.side, o.action, fl.shares, fl.avg_price, fl.fee)
                    self.trades.row(f"{now:.3f}", wm.slug, o.side, o.action, o.reason, o.price, f"{fl.shares:.2f}",
                                    f"{fl.avg_price:.4f}", f"{fl.fee:.4f}", f"{o.edge:.4f}", f"{fair.q:.4f}",
                                    f"{wm.t_end - now:.1f}")
                    log.info("%s %s %-4s %7.2f @ %.3f fee=%.3f edge=%.3f q=%.3f | up=%.1f down=%.1f worst=%.2f",
                             o.reason, o.action, o.side, fl.shares, fl.avg_price, fl.fee, o.edge, fair.q,
                             inv.n_up, inv.n_down, inv.worst_case_pnl())
        finally:
            book_task.cancel()
        asyncio.create_task(self._settle(wm, strike, inv))

    async def _settle(self, wm: WindowMarket, strike: float, inv: Inventory):
        if inv.n_trades == 0:
            return
        close = await self.chainlink.wait_price_at(wm.t_end, self.cfg.settle_delay_sec + 30)
        if close is None:
            log.warning("no close price for %s; pnl unknown", wm.slug)
            return
        up_won = close >= strike
        pnl = inv.settle(up_won)
        self.total_pnl += pnl
        self.n_windows += 1
        self.n_win_windows += pnl > 0
        self.windows.row(wm.slug, f"{strike:.2f}", f"{close:.2f}", up_won, f"{inv.n_up:.2f}", f"{inv.n_down:.2f}",
                         f"{inv.spent:.2f}", f"{inv.fees:.4f}", f"{pnl:.4f}", f"{inv.locked_pnl():.4f}")
        log.info("SETTLE %s %s pnl=%.2f locked=%.2f | total=%.2f over %d windows (%.0f%% profitable)",
                 wm.slug, "UP" if up_won else "DOWN", pnl, inv.locked_pnl(), self.total_pnl, self.n_windows,
                 100.0 * self.n_win_windows / self.n_windows)
