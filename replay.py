"""Replay na PRAVIM BTC cijenama: zadnjih N završenih 5-min prozora.

Povuče 1-sekundne Binance cijene (BTCUSDT) za zadnjih N prozora + 10 min prije
za procjenu volatilnosti, pa na stvarnom kretanju BTC-a pusti bota protiv
simuliranog Polymarket market makera koji kasni `--mm-lag` sekundi.

Napomena: povijesna Polymarket knjiga naloga nije javno dostupna, zato je
strana Polymarketa simulirana (ista kao u simulate.py). Ako je Gamma API
dostupan, skripta usporedi i stvarni ishod tržišta s ishodom po Binanceu.

    python replay.py                    # zadnjih 10 prozora
    python replay.py --last 20 --mm-lag 1.0
    python replay.py --csv cijene.csv   # offline: CSV s kolonama ts,price (unix s, 1-s cijene)
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import time
import urllib.request

from polybot.config import Config
from simulate import add_world_args, run_window

KLINE_HOSTS = [
    "https://api.binance.com",
    "https://data-api.binance.vision",
    "https://api.binance.us",
]


def _get_json(url: str, timeout: float = 10):
    req = urllib.request.Request(url, headers={"User-Agent": "polybot-replay"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def fetch_1s_closes(t_from: int, t_to: int) -> dict[int, float]:
    """Vrati {unix_sekunda: close} za [t_from, t_to). Pokušava više Binance hostova."""
    last_err = None
    for host in KLINE_HOSTS:
        out: dict[int, float] = {}
        try:
            cur = t_from
            while cur < t_to:
                url = (f"{host}/api/v3/klines?symbol=BTCUSDT&interval=1s"
                       f"&startTime={cur * 1000}&endTime={t_to * 1000 - 1}&limit=1000")
                rows = _get_json(url)
                if not rows:
                    break
                for r in rows:
                    out[int(r[0]) // 1000] = float(r[4])
                cur = int(rows[-1][0]) // 1000 + 1
            if out:
                print(f"[data] {len(out)} sekundi s {host}")
                return out
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"[data] {host} nedostupan: {e}")
    raise SystemExit(f"Ne mogu dohvatiti Binance podatke ({last_err}). Probaj --csv.")


def load_csv(path: str) -> dict[int, float]:
    out = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            out[int(float(row["ts"]))] = float(row["price"])
    return out


def series(closes: dict[int, float], t_from: int, t_to: int) -> list[float]:
    """1-s niz s forward-fillom rupa."""
    keys = sorted(closes)
    last = closes[keys[0]]
    out = []
    for t in range(t_from, t_to):
        last = closes.get(t, last)
        out.append(last)
    return out


def to_grid(sec: list[float], dt: float = 0.1) -> list[float]:
    """1-s cijene -> mreža od 0.1 s (cijena drži zadnju vrijednost unutar sekunde)."""
    k = int(round(1 / dt))
    grid = []
    for p in sec[:-1]:
        grid.extend([p] * k)
    grid.append(sec[-1])
    return grid


def pm_outcome(cfg: Config, t_start: int) -> str:
    try:
        ev = _get_json(f"{cfg.gamma_host}/events?slug={cfg.slug_prefix}{t_start}", timeout=5)
        m = ev[0]["markets"][0]
        prices = json.loads(m["outcomePrices"]) if isinstance(m["outcomePrices"], str) else m["outcomePrices"]
        outs = json.loads(m["outcomes"]) if isinstance(m["outcomes"], str) else m["outcomes"]
        if max(float(x) for x in prices) < 0.99:
            return "?"
        return str(outs[[float(x) for x in prices].index(max(float(x) for x in prices))]).upper()
    except Exception:  # noqa: BLE001
        return "-"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--last", type=int, default=10, help="broj zadnjih završenih 5-min prozora")
    ap.add_argument("--csv", type=str, help="offline CSV (ts,price) umjesto Binance API-ja")
    ap.add_argument("--end", type=int, help="unix kraj zadnjeg prozora (default: zadnji završeni)")
    ap.add_argument("--no-pm-check", action="store_true", help="ne provjeravaj stvarni ishod na Polymarketu")
    add_world_args(ap)
    a = ap.parse_args()

    cfg = Config()
    if a.bankroll:
        cfg.apply_bankroll(a.bankroll)
    if a.no_fee:
        cfg.fee_rate = 0.0
    W = cfg.window_sec
    warm = 600

    if a.csv:
        closes = load_csv(a.csv)
        end = a.end or (max(closes) // W) * W
    else:
        end = a.end or (int(time.time()) // W) * W
        closes = fetch_1s_closes(end - a.last * W - warm, end + 1)
    first = end - a.last * W
    if min(closes) > first - warm:
        print("[upozorenje] nema punih 10 min zagrijavanja za prvi prozor")

    rng = random.Random(a.seed)
    print(f"\nmm_lag={a.mm_lag}s  requote={a.mm_requote}s  exec_lat={a.exec_latency}s  "
          f"competitor={a.competitor_prob:.0%}  fee={'off' if a.no_fee else 'on'}\n")
    hdr = f"{'prozor (UTC)':<17}{'strike':>10}{'close':>10} {'ishod':<6}{'PM':<6}{'UP':>7}{'DOWN':>7}{'nalozi':>7}{'fee':>7}{'najgore':>9}{'PnL $':>9}{'stanje':>9}"
    print(hdr)
    print("-" * len(hdr))
    total = 0.0
    balance = cfg.bankroll_usd
    stopped = False
    wins = traded = 0
    legs_w = legs_b = 0
    for k in range(a.last):
        t0 = first + k * W
        sec = series(closes, t0, t0 + W + 1)
        warmup = series(closes, t0 - warm, t0)
        if cfg.max_loss_usd > 0 and total <= -cfg.max_loss_usd:
            stopped = True
            break
        r = run_window(cfg, rng, a, path=to_grid(sec), warmup=warmup)
        total += r["pnl"]
        balance += r["pnl"]
        if r["n_trades"]:
            traded += 1
            wins += r["pnl"] > 0
        legs_w += r["leg_wins"]
        legs_b += r["leg_buys"]
        pm = "-" if a.no_pm_check or a.csv else pm_outcome(cfg, t0)
        ts = time.strftime("%m-%d %H:%M", time.gmtime(t0))
        print(f"{ts:<17}{r['strike']:>10.2f}{r['close']:>10.2f} {'UP' if r['up_won'] else 'DOWN':<6}{pm:<6}"
              f"{r['n_up']:>7.1f}{r['n_down']:>7.1f}{r['n_trades']:>7}{r['fees']:>7.2f}{r['worst']:>9.2f}{r['pnl']:>9.2f}{balance:>9.2f}")
    print("-" * len(hdr))
    if stopped:
        print(f"STOP-LOSS aktiviran (gubitak >= {cfg.max_loss_usd:.2f})")
    print(f"bankroll {cfg.bankroll_usd:.2f} -> {balance:.2f}  ({100 * total / cfg.bankroll_usd:+.1f}%)   "
          f"limiti: nalog {cfg.max_order_usd:.2f}, prozor {cfg.max_window_usd:.2f}, stop-loss {cfg.max_loss_usd:.2f}")
    print(f"UKUPNO PnL: {total:+.2f} $   |   profitabilnih prozora: {wins}/{traded}   |   "
          f"pogodak smjera po nalogu: {100 * legs_w / max(legs_b, 1):.0f}% ({legs_b} kupnji)")
    print("\n'najgore' = zaključani PnL u najgorem ishodu (>0 znači profit siguran bez obzira na smjer)")
    print("Polymarket strana je SIMULIRANA (povijesna knjiga nije javna) - rezultat ovisi o --mm-lag.")


if __name__ == "__main__":
    main()
