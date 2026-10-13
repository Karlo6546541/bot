"""Izvršenje: paper (simulirano na živoj knjizi) i live (py-clob-client, FAK nalozi)."""
from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from typing import Callable

from .config import Config
from .strategy import BUY, Book, Order
from .mathcore import taker_fee_per_share

log = logging.getLogger("polybot.exec")


@dataclass
class Fill:
    shares: float
    avg_price: float
    fee: float


def match_against_book(book: Book, order: Order, cfg: Config, consume: bool = True) -> Fill:
    """FAK semantika: uzmi sve nivoe do limit cijene, ostatak se poništava."""
    levels = book.asks if order.action == BUY else book.bids
    remaining = order.shares
    shares = notional = fee = 0.0
    new_levels = []
    for idx, (p, s) in enumerate(levels):
        ok = p <= order.price + 1e-9 if order.action == BUY else p >= order.price - 1e-9
        if not ok or remaining <= 1e-9:
            new_levels.extend(levels[idx:])
            break
        take = min(s, remaining)
        shares += take
        notional += take * p
        fee += take * taker_fee_per_share(p, cfg.fee_rate, cfg.fee_exp)
        remaining -= take
        if s - take > 1e-9:
            new_levels.append((p, s - take))
    if consume:
        if order.action == BUY:
            book.asks = new_levels
        else:
            book.bids = new_levels
    if shares <= 0:
        return Fill(0.0, 0.0, 0.0)
    return Fill(shares, notional / shares, fee)


class PaperBroker:
    def __init__(self, cfg: Config, book_getter: Callable[[str], Book]):
        self.cfg = cfg
        self.book_getter = book_getter

    async def execute(self, order: Order, token_id: str) -> Fill:
        # simuliraj mrežno kašnjenje + potpisivanje: knjiga se u međuvremenu može pomaknuti
        await asyncio.sleep(self.cfg.paper_latency_ms / 1000.0)
        return match_against_book(self.book_getter(order.side), order, self.cfg)


class LiveBroker:
    """Pravi nalozi. Zahtijeva env: POLY_PRIVATE_KEY, opcionalno POLY_FUNDER, POLY_SIGNATURE_TYPE."""

    def __init__(self, cfg: Config):
        from py_clob_client.client import ClobClient  # type: ignore

        pk = os.environ["POLY_PRIVATE_KEY"]
        funder = os.environ.get("POLY_FUNDER")
        sig_type = int(os.environ.get("POLY_SIGNATURE_TYPE", "0"))
        kwargs = dict(key=pk, chain_id=137, signature_type=sig_type)
        if funder:
            kwargs["funder"] = funder
        self.client = ClobClient(cfg.clob_host, **kwargs)
        self.client.set_api_creds(self.client.create_or_derive_api_creds())
        self.cfg = cfg

    def _post(self, order: Order, token_id: str) -> Fill:
        from py_clob_client.clob_types import OrderArgs, OrderType  # type: ignore
        from py_clob_client.order_builder.constants import BUY as C_BUY, SELL as C_SELL  # type: ignore

        args = OrderArgs(
            token_id=token_id,
            price=round(order.price, 2),
            size=round(order.shares, 2),
            side=C_BUY if order.action == BUY else C_SELL,
        )
        signed = self.client.create_order(args)
        resp = self.client.post_order(signed, OrderType.FAK)
        if not resp or not resp.get("success", False):
            log.warning("order rejected: %s", resp)
            return Fill(0.0, 0.0, 0.0)
        making = float(resp.get("makingAmount") or 0)
        taking = float(resp.get("takingAmount") or 0)
        # BUY: making = USDC, taking = dionice; SELL: obrnuto
        shares, usdc = (taking, making) if order.action == BUY else (making, taking)
        if shares <= 0:
            return Fill(0.0, 0.0, 0.0)
        px = usdc / shares
        fee = shares * taker_fee_per_share(px, self.cfg.fee_rate, self.cfg.fee_exp)
        return Fill(shares, px, fee)

    async def execute(self, order: Order, token_id: str) -> Fill:
        try:
            return await asyncio.to_thread(self._post, order, token_id)
        except Exception as e:  # noqa: BLE001
            log.exception("live order failed: %s", e)
            return Fill(0.0, 0.0, 0.0)
