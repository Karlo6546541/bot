"""Websocket feedovi: Binance (brzi), Polymarket RTDS Chainlink (rezolucija), CLOB knjiga."""
from __future__ import annotations

import asyncio
import bisect
import json
import logging
import math
import time
from collections import deque
from typing import Callable

import websockets

from .config import Config
from .mathcore import EwmaMean, EwmaVol, annual_to_sec_sigma
from .strategy import Book

log = logging.getLogger("polybot.feeds")


async def _reconnecting(name: str, url: str, on_open, on_msg, ping_text: str | None = None, ping_every: float = 5.0):
    backoff = 1.0
    while True:
        try:
            async with websockets.connect(url, ping_interval=20, max_size=2**23) as ws:
                log.info("%s connected", name)
                backoff = 1.0
                await on_open(ws)
                pinger = None
                if ping_text:
                    async def _ping():
                        while True:
                            await asyncio.sleep(ping_every)
                            await ws.send(ping_text)
                    pinger = asyncio.create_task(_ping())
                try:
                    async for raw in ws:
                        if raw in ("PONG", "PING", b"PONG"):
                            continue
                        on_msg(raw)
                finally:
                    if pinger:
                        pinger.cancel()
        except asyncio.CancelledError:
            raise
        except Exception as e:  # noqa: BLE001
            log.warning("%s disconnected: %s (retry %.0fs)", name, e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30)


class PriceHistory:
    def __init__(self, keep_sec: float = 900):
        self.ts: deque[float] = deque()
        self.px: deque[float] = deque()
        self.keep = keep_sec

    def add(self, t: float, p: float) -> None:
        self.ts.append(t)
        self.px.append(p)
        while self.ts and self.ts[0] < t - self.keep:
            self.ts.popleft()
            self.px.popleft()

    def at(self, t: float) -> float | None:
        """Zadnja cijena s timestampom <= t."""
        if not self.ts:
            return None
        i = bisect.bisect_right(self.ts, t) - 1
        return self.px[max(i, 0)]

    @property
    def last(self) -> float | None:
        return self.px[-1] if self.px else None

    @property
    def last_t(self) -> float:
        return self.ts[-1] if self.ts else 0.0


class BinanceFeed:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.hist = PriceHistory(keep_sec=120)
        self.vol = EwmaVol(annual_to_sec_sigma(cfg.sigma_prior_annual), cfg.vol_halflife_sec, cfg.vol_sample_sec)
        self.listeners: list[Callable[[], None]] = []

    def _on_msg(self, raw) -> None:
        m = json.loads(raw)
        if "b" not in m or "a" not in m:
            return
        mid = (float(m["b"]) + float(m["a"])) / 2.0
        t = time.time()
        self.hist.add(t, mid)
        self.vol.update(mid, t)
        for cb in self.listeners:
            cb()

    async def run(self):
        async def on_open(ws):
            return None
        await _reconnecting("binance", self.cfg.binance_ws, on_open, self._on_msg)


class ChainlinkFeed:
    """Polymarket RTDS, topic crypto_prices_chainlink, btc/usd. Ovo je cijena po kojoj se tržište rješava."""

    def __init__(self, cfg: Config, binance: BinanceFeed):
        self.cfg = cfg
        self.hist = PriceHistory(keep_sec=1800)
        self.binance = binance
        self.basis = EwmaMean(cfg.basis_halflife_sec, init_var=(2e-4) ** 2)

    def _ingest(self, t: float, p: float) -> None:
        if self.hist.ts and t <= self.hist.last_t:
            return
        self.hist.add(t, p)
        bn = self.binance.hist.at(t)
        if bn:
            self.basis.update(math.log(p / bn), t)

    def _on_msg(self, raw) -> None:
        try:
            m = json.loads(raw)
        except (ValueError, TypeError):
            return
        if m.get("topic") != "crypto_prices_chainlink":
            return
        pl = m.get("payload") or {}
        if pl.get("symbol", "btc/usd").lower() != "btc/usd":
            return
        if isinstance(pl.get("data"), list):  # inicijalni snapshot
            for row in pl["data"]:
                self._ingest(float(row["timestamp"]) / 1000.0, float(row["value"]))
        elif "value" in pl:
            self._ingest(float(pl["timestamp"]) / 1000.0, float(pl["value"]))

    async def run(self):
        sub = {
            "action": "subscribe",
            "subscriptions": [
                {"topic": "crypto_prices_chainlink", "type": "*", "filters": json.dumps({"symbol": "btc/usd"})}
            ],
        }

        async def on_open(ws):
            await ws.send(json.dumps(sub))

        await _reconnecting("chainlink", self.cfg.rtds_ws, on_open, self._on_msg, ping_text="PING")

    def price_at(self, t: float) -> float | None:
        return self.hist.at(t)

    async def wait_price_at(self, t: float, timeout: float) -> float | None:
        """Čekaj dok ne stigne tick s timestampom >= t, pa vrati cijenu na t."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.hist.last_t >= t:
                return self.hist.at(t)
            await asyncio.sleep(0.1)
        return None


class BookFeed:
    """CLOB market kanal za dva tokena (UP, DOWN)."""

    def __init__(self, cfg: Config, token_ids: dict[str, str]):
        self.cfg = cfg
        self.token_ids = token_ids                     # side -> token
        self.side_of = {v: k for k, v in token_ids.items()}
        self._bids: dict[str, dict[float, float]] = {s: {} for s in token_ids}
        self._asks: dict[str, dict[float, float]] = {s: {} for s in token_ids}
        self.books: dict[str, Book] = {s: Book() for s in token_ids}
        self.ready = asyncio.Event()

    def _rebuild(self, side: str) -> None:
        b = self.books[side]
        b.bids = sorted(((p, s) for p, s in self._bids[side].items() if s > 0), reverse=True)
        b.asks = sorted((p, s) for p, s in self._asks[side].items() if s > 0)
        b.ts = time.time()

    def _apply_level(self, side: str, book_side: str, price: float, size: float) -> None:
        d = self._bids[side] if book_side.upper() in ("BUY", "BID", "BIDS") else self._asks[side]
        if size <= 0:
            d.pop(price, None)
        else:
            d[price] = size

    def _handle(self, m: dict) -> None:
        et = m.get("event_type")
        if et == "book":
            side = self.side_of.get(m.get("asset_id"))
            if not side:
                return
            self._bids[side] = {float(x["price"]): float(x["size"]) for x in m.get("bids", [])}
            self._asks[side] = {float(x["price"]): float(x["size"]) for x in m.get("asks", [])}
            self._rebuild(side)
            if all(self.books[s].ts > 0 for s in self.books):
                self.ready.set()
        elif et == "price_change":
            touched = set()
            changes = m.get("price_changes") or m.get("changes") or []
            for ch in changes:
                side = self.side_of.get(ch.get("asset_id") or m.get("asset_id"))
                if not side:
                    continue
                self._apply_level(side, ch["side"], float(ch["price"]), float(ch["size"]))
                touched.add(side)
            for s in touched:
                self._rebuild(s)

    def _on_msg(self, raw) -> None:
        try:
            m = json.loads(raw)
        except (ValueError, TypeError):
            return
        for item in m if isinstance(m, list) else [m]:
            if isinstance(item, dict):
                self._handle(item)

    async def run(self):
        sub = {"assets_ids": list(self.token_ids.values()), "type": "market"}

        async def on_open(ws):
            await ws.send(json.dumps(sub))

        await _reconnecting("clob-book", self.cfg.clob_ws, on_open, self._on_msg, ping_text="PING", ping_every=10)
