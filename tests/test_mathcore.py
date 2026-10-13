import math

import pytest

from polybot.mathcore import (
    EwmaVol, annual_to_sec_sigma, betainc_reg, mv_target_shares, norm_cdf, prob_density, prob_up,
    student_t_cdf, taker_fee_per_share,
)


@pytest.mark.parametrize("p,expected", [(0.10, 0.2025), (0.50, 1.5625), (0.99, 0.00245)])
def test_fee_matches_polymarket_examples(p, expected):
    # Polymarket docs: 100 dionica @0.10 -> ~0.20$, @0.50 -> 1.56$, @0.99 -> ~0.0025$
    assert 100 * taker_fee_per_share(p) == pytest.approx(expected, rel=1e-2)


def test_student_t_cdf_known_values():
    assert student_t_cdf(0.0, 5) == pytest.approx(0.5)
    assert student_t_cdf(2.0, 5) == pytest.approx(0.94903, abs=1e-4)
    assert student_t_cdf(-2.0, 5) == pytest.approx(1 - 0.94903, abs=1e-4)
    assert student_t_cdf(1.96, 1e6) == pytest.approx(norm_cdf(1.96), abs=1e-4)
    assert betainc_reg(2, 3, 0.4) == pytest.approx(0.5248, abs=1e-4)


def test_prob_up_basic():
    s = annual_to_sec_sigma(0.5)
    assert prob_up(100, 100, s, 300) == pytest.approx(0.5, abs=1e-3)
    assert prob_up(100.2, 100, s, 300) > 0.6
    assert prob_up(99.8, 100, s, 300) < 0.4
    assert prob_up(100.01, 100, s, 0) == 1.0
    # simetrija
    assert prob_up(100.1, 100, s, 120, 4) + prob_up(100, 100.1, s, 120, 4) == pytest.approx(1, abs=2e-3)


def test_density_is_derivative():
    s = annual_to_sec_sigma(0.6)
    for nu in (0, 4):
        S, K, tau, h = 100.05, 100, 100, 1e-6
        num = (prob_up(S * math.exp(h), K, s, tau, nu) - prob_up(S * math.exp(-h), K, s, tau, nu)) / (2 * h)
        assert prob_density(S, K, s, tau, nu)[0] == pytest.approx(num, rel=1e-3)


def test_mv_target_hedges_imbalance():
    # bez edgea, s viškom 40 UP dionica -> želi -40 (tj. prodati / hedgeati)
    assert mv_target_shares(0.5, 0.5, 40, 250) == pytest.approx(-40)
    # 2c edge, balansirano: R*edge/var = 250*0.02/0.25 = 20
    assert mv_target_shares(0.5, 0.48, 0, 250) == pytest.approx(20)


def test_ewma_vol_converges():
    import random
    rng = random.Random(1)
    sig = annual_to_sec_sigma(0.8)
    v = EwmaVol(annual_to_sec_sigma(0.3), halflife_sec=200)
    p = 100.0
    for t in range(5000):
        p *= math.exp(sig * rng.gauss(0, 1))
        v.update(p, t)
    assert v.sigma == pytest.approx(sig, rel=0.15)
