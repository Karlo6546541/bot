"""Matematička jezgra.

Notacija
--------
S      efektivna spot cijena (Binance * exp(baza)) -> procjena Chainlink cijene
K      strike = Chainlink cijena na početku 5-min prozora ("price to beat")
tau    sekunde do isteka
sigma  volatilnost po sqrt(sekundi)
q      fer vjerojatnost da UP pobijedi = P(S_T >= K)

Fer vjerojatnost (driftless log-random-walk, opcionalno Student-t repovi):
    d = (ln(S/K) - sigma^2 tau / 2) / (sigma sqrt(tau))
    q = Phi(d)                              (normalna)
    q = F_nu(d * sqrt(nu/(nu-2)))           (Student-t skaliran na jediničnu varijancu)

Fee (Polymarket crypto up/down, taker):
    fee(p) = rate * (p(1-p))^exp  po dionici, default rate=0.25, exp=2
    -> efektivna kupovna cijena  a_eff = a + fee(a)
    -> efektivna prodajna cijena b_eff = b - fee(b)

Veličina (mean-variance == frakcijski Kelly za male edgeove):
    Ishod po dionici UP je Bernoulli(q); varijanca portfelja = q(1-q) * D^2,
    gdje je D = n_up - n_down (neuparene dionice). Maksimizacija
    E[PnL] - Var[PnL]/(2R)  po x dionica kupljenih po a_eff daje
        x* = R * (q - a_eff) / (q(1-q)) - D
    R = kelly_mult * bankroll. Za a ~ q to je točno Kelly ulog W(q-a)/(a(1-a)).
    Član "-D" automatski tjera bota da hedgea neuparene dionice.

Zaključavanje (pair lock):
    Ako imamo n_up > n_down i kupimo DOWN po b_eff takvom da
        avg_cost_up + b_eff <= 1 - margin,
    svaki par UP+DOWN isplaćuje točno 1 -> profit zaključan bez obzira na ishod.
    Najgori-slučaj PnL = cash + min(n_up, n_down) strogo raste sa svakim takvim lockom.
"""
from __future__ import annotations

import math

SQRT2 = math.sqrt(2.0)
SQRT2PI = math.sqrt(2.0 * math.pi)
SECONDS_PER_YEAR = 365.0 * 24 * 3600


# ---------------------------------------------------------------- distribucije
def norm_cdf(x: float) -> float:
    return 0.5 * math.erfc(-x / SQRT2)


def norm_pdf(x: float) -> float:
    return math.exp(-0.5 * x * x) / SQRT2PI


def _betacf(a: float, b: float, x: float) -> float:
    """Lentzov verižni razlomak za nepotpunu beta funkciju (Numerical Recipes)."""
    tiny = 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 300):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 1e-12:
            break
    return h


def betainc_reg(a: float, b: float, x: float) -> float:
    """Regularizirana nepotpuna beta I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    lbt = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
    bt = math.exp(lbt)
    if x < (a + 1.0) / (a + b + 2.0):
        return bt * _betacf(a, b, x) / a
    return 1.0 - bt * _betacf(b, a, 1.0 - x) / b


def student_t_cdf(t: float, nu: float) -> float:
    x = nu / (nu + t * t)
    tail = 0.5 * betainc_reg(nu / 2.0, 0.5, x)
    return 1.0 - tail if t > 0 else tail


def student_t_pdf(t: float, nu: float) -> float:
    lc = math.lgamma((nu + 1) / 2) - math.lgamma(nu / 2) - 0.5 * math.log(nu * math.pi)
    return math.exp(lc - (nu + 1) / 2 * math.log1p(t * t / nu))


# ---------------------------------------------------------------- fee
def taker_fee_per_share(p: float, rate: float = 0.25, exp: float = 2.0) -> float:
    p = min(max(p, 0.0), 1.0)
    return rate * (p * (1.0 - p)) ** exp


def eff_buy(p: float, rate: float = 0.25, exp: float = 2.0) -> float:
    return p + taker_fee_per_share(p, rate, exp)


def eff_sell(p: float, rate: float = 0.25, exp: float = 2.0) -> float:
    return p - taker_fee_per_share(p, rate, exp)


# ---------------------------------------------------------------- fer vrijednost
def annual_to_sec_sigma(sigma_annual: float) -> float:
    return sigma_annual / math.sqrt(SECONDS_PER_YEAR)


def _d(spot: float, strike: float, sigma_sec: float, tau_sec: float) -> tuple[float, float]:
    s = sigma_sec * math.sqrt(tau_sec)
    return (math.log(spot / strike) - 0.5 * s * s) / s, s


def prob_up(spot: float, strike: float, sigma_sec: float, tau_sec: float, nu: float = 0.0) -> float:
    """P(S_T >= K)."""
    if tau_sec <= 0 or sigma_sec <= 0:
        return 1.0 if spot >= strike else 0.0
    d, _ = _d(spot, strike, sigma_sec, tau_sec)
    if nu and nu > 2:
        return student_t_cdf(d * math.sqrt(nu / (nu - 2.0)), nu)
    return norm_cdf(d)


def prob_density(spot: float, strike: float, sigma_sec: float, tau_sec: float, nu: float = 0.0) -> tuple[float, float]:
    """Vraća (dq/d lnS, d). Koristi se za Delta i za propagaciju nesigurnosti."""
    if tau_sec <= 0 or sigma_sec <= 0:
        return 0.0, 0.0
    d, s = _d(spot, strike, sigma_sec, tau_sec)
    if nu and nu > 2:
        k = math.sqrt(nu / (nu - 2.0))
        return student_t_pdf(d * k, nu) * k / s, d
    return norm_pdf(d) / s, d


# ---------------------------------------------------------------- estimatori
class EwmaVol:
    """EWMA varijanca log-povrata po sekundi, s re-uzorkovanjem (izbjegava bid/ask bounce)."""

    def __init__(self, sigma_prior_sec: float, halflife_sec: float, sample_sec: float = 1.0):
        self.var = sigma_prior_sec ** 2
        self.halflife = halflife_sec
        self.sample = sample_sec
        self._last_t: float | None = None
        self._last_p: float | None = None
        self.n = 0

    def update(self, price: float, t: float) -> None:
        if self._last_t is None:
            self._last_t, self._last_p = t, price
            return
        dt = t - self._last_t
        if dt < self.sample:
            return
        r = math.log(price / self._last_p)
        w = 1.0 - math.exp(-dt * math.log(2) / self.halflife)
        self.var = (1 - w) * self.var + w * (r * r / dt)
        self._last_t, self._last_p = t, price
        self.n += 1

    @property
    def sigma(self) -> float:
        return math.sqrt(self.var)


class EwmaMean:
    """EWMA srednja vrijednost + varijanca reziduala (za bazu Chainlink/Binance)."""

    def __init__(self, halflife_sec: float, init: float = 0.0, init_var: float = 1e-8):
        self.mean = init
        self.var = init_var
        self.halflife = halflife_sec
        self._last_t: float | None = None
        self.n = 0

    def update(self, x: float, t: float) -> None:
        if self._last_t is None or self.n == 0:
            self.mean, self._last_t, self.n = x, t, 1
            return
        dt = max(t - self._last_t, 1e-3)
        w = 1.0 - math.exp(-dt * math.log(2) / self.halflife)
        resid = x - self.mean
        self.mean += w * resid
        self.var = (1 - w) * self.var + w * resid * resid
        self._last_t = t
        self.n += 1

    @property
    def std(self) -> float:
        return math.sqrt(max(self.var, 0.0))


# ---------------------------------------------------------------- sizing
def mv_target_shares(q_side: float, price_eff: float, imbalance_side: float, risk_tol_usd: float) -> float:
    """x* = R (q - a_eff) / (q(1-q)) - D.  Negativno => poželjno prodati."""
    var = max(q_side * (1.0 - q_side), 0.01)
    return risk_tol_usd * (q_side - price_eff) / var - imbalance_side


def kelly_fraction(q: float, price_eff: float) -> float:
    if price_eff >= 1.0:
        return 0.0
    return max(0.0, (q - price_eff) / (1.0 - price_eff))
