"""Otkrivanje 5-min BTC Up/Down tržišta preko Gamma API-ja (slug btc-updown-5m-<unix start>)."""
from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass

import aiohttp

from .config import Config

log = logging.getLogger("polybot.market")


@dataclass
class WindowMarket:
    slug: str
    t_start: int
    t_end: int
    condition_id: str
    token_up: str
    token_down: str
    price_to_beat: float | None = None


def _parse_list(x):
    return json.loads(x) if isinstance(x, str) else (x or [])


def parse_event(ev: dict, t_start: int, window_sec: int) -> WindowMarket | None:
    markets = ev.get("markets") or []
    if not markets:
        return None
    m = markets[0]
    outcomes = [o.lower() for o in _parse_list(m.get("outcomes"))]
    tokens = _parse_list(m.get("clobTokenIds"))
    if len(tokens) != 2:
        return None
    iu = outcomes.index("up") if "up" in outcomes else 0
    idn = 1 - iu
    ptb = None
    meta = ev.get("eventMetadata") or m.get("eventMetadata") or {}
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except ValueError:
            meta = {}
    if isinstance(meta, dict) and meta.get("priceToBeat"):
        ptb = float(meta["priceToBeat"])
    return WindowMarket(
        slug=ev.get("slug", ""),
        t_start=t_start,
        t_end=t_start + window_sec,
        condition_id=m.get("conditionId", ""),
        token_up=str(tokens[iu]),
        token_down=str(tokens[idn]),
        price_to_beat=ptb,
    )


async def find_window(cfg: Config, session: aiohttp.ClientSession, t_start: int, timeout: float = 60) -> WindowMarket | None:
    slug = f"{cfg.slug_prefix}{t_start}"
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        try:
            async with session.get(f"{cfg.gamma_host}/events", params={"slug": slug}, timeout=aiohttp.ClientTimeout(total=5)) as r:
                data = await r.json()
            if data:
                wm = parse_event(data[0], t_start, cfg.window_sec)
                if wm:
                    return wm
        except Exception as e:  # noqa: BLE001
            log.warning("gamma lookup %s failed: %s", slug, e)
        await asyncio.sleep(2)
    return None
