import math

from polybot.config import Config
from polybot.execution import match_against_book
from polybot.mathcore import annual_to_sec_sigma
from polybot.strategy import BUY, DOWN, UP, Book, Inventory, MarketView, Order, Strategy


def view(spot, spot_lb, up, down, t=100.0, strike=60000.0):
    return MarketView(t_now=t, t_start=0, t_end=300, strike=strike, spot=spot, spot_lookback=spot_lb,
                      basis=0.0, basis_std=1e-5, sigma_sec=annual_to_sec_sigma(0.5), up=up, down=down)


def books(up_bid, up_ask, size=200):
    up = Book([(up_bid, size)], [(up_ask, size)])
    dn = Book([(round(1 - up_ask, 2), size)], [(round(1 - up_bid, 2), size)])
    return up, dn


def test_no_trade_when_fair():
    s = Strategy(Config())
    up, dn = books(0.49, 0.51)
    assert s.decide(view(60000, 60000, up, dn), Inventory()) == []


def test_latency_buy_up_after_binance_jump():
    s = Strategy(Config())
    up, dn = books(0.49, 0.51)                      # PM još na 50/50
    v = view(60060, 60000, up, dn)                  # Binance +10bp u zadnje 2 s
    q = s.fair(v).q
    assert q > 0.6
    orders = s.decide(v, Inventory())
    assert len(orders) == 1 and orders[0].side == UP and orders[0].action == BUY
    assert orders[0].reason.startswith("LATENCY")


def test_unexplained_edge_is_ignored():
    # model kaže q>0.6, ali Binance se NIJE pomaknuo nedavno -> vjerojatno greška modela/strikea
    s = Strategy(Config())
    up, dn = books(0.49, 0.51)
    assert s.decide(view(60060, 60060, up, dn), Inventory()) == []


def test_lock_leg_buys_other_side_cheaply():
    s = Strategy(Config())
    inv = Inventory()
    inv.apply_fill(UP, BUY, 50, 0.45, 0.0)
    up, dn = books(0.45, 0.47)                      # DOWN ask = 0.55 -> 0.45+0.55+fee > 0.99 -> nema locka
    assert all(o.reason != "LOCK" for o in s.decide(view(60000, 60000, up, dn), inv))
    up, dn = books(0.55, 0.57)                      # DOWN ask 0.45 -> par = 0.45+0.45+fee ~0.93
    orders = s.decide(view(60000, 60000, up, dn), inv)
    lock = [o for o in orders if o.side == DOWN]
    assert lock and lock[0].reason.startswith("LOCK") and lock[0].shares >= 50 - 1e-9


def test_complete_set_arb():
    s = Strategy(Config())
    up = Book([(0.44, 100)], [(0.46, 100)])
    dn = Book([(0.44, 100)], [(0.47, 100)])        # 0.46+0.47 + fee ~0.96 < 0.99
    orders = s.decide(view(60000, 60000, up, dn), Inventory())
    assert {o.side for o in orders} == {UP, DOWN}
    assert all(o.reason == "COMPLETE_SET" for o in orders)


def test_locked_pair_pays_regardless_of_outcome():
    inv = Inventory()
    inv.apply_fill(UP, BUY, 100, 0.45, 100 * 0.25 * (0.45 * 0.55) ** 2)
    inv.apply_fill(DOWN, BUY, 100, 0.47, 100 * 0.25 * (0.47 * 0.53) ** 2)
    assert inv.settle(True) == inv.settle(False) > 0
    assert inv.worst_case_pnl() > 0


def test_match_against_book_respects_limit_and_consumes():
    b = Book([], [(0.50, 10), (0.51, 10), (0.53, 10)])
    fl = match_against_book(b, Order(UP, BUY, 0.51, 25, "x"), Config())
    assert fl.shares == 20 and math.isclose(fl.avg_price, 0.505)
    assert b.asks == [(0.53, 10)]


def test_no_trading_near_expiry():
    s = Strategy(Config())
    up, dn = books(0.49, 0.51)
    assert s.decide(view(60060, 60000, up, dn, t=290), Inventory()) == []
