from pytest import approx
from brownie.test import given, strategy
from decimal import Decimal


@given(
    oi_long=strategy('decimal', min_value='0.001', max_value='800000',
                     places=3),
    oi_short=strategy('decimal', min_value='0.001', max_value='800000',
                      places=3),
    dt=strategy('uint256', min_value='0', max_value='7776000'))
def test_oi_after_funding(market, oi_long, oi_short, dt):
    oi_long = oi_long * Decimal(1e18)
    oi_short = oi_short * Decimal(1e18)
    oi_overweight = oi_long if oi_long >= oi_short else oi_short
    oi_underweight = oi_short if oi_long >= oi_short else oi_long

    oi = oi_long + oi_short
    oi_imb = oi_long - oi_short if oi_long >= oi_short else oi_short - oi_long

    timestamp_last = 1642797758
    timestamp_now = timestamp_last + dt

    # calculate expected oi values long and short
    k = market.k() / Decimal(1e18)
    oi_imb *= (1 - 2*k) ** (dt)
    expect_oi_overweight = int((oi + oi_imb) / 2)
    expect_oi_underweight = int((oi - oi_imb) / 2)

    # get actual oi values long and short
    actual_oi_overweight, actual_oi_underweight = market.oiAfterFunding(
        oi_overweight, oi_underweight, timestamp_last, timestamp_now)

    # check expect oi values equal actual oi values after funding
    assert int(actual_oi_overweight) == approx(expect_oi_overweight)
    assert int(actual_oi_underweight) == approx(expect_oi_underweight)


def test_oi_after_funding_when_longs_and_shorts_are_zero(market):
    oi_long = 0
    oi_short = 0
    timestamp_last = 1643247197
    timestamp_now = 1643247797

    actual_oi_overweight, actual_oi_underweight = market.oiAfterFunding(
        oi_long, oi_short, timestamp_last, timestamp_now)

    assert actual_oi_overweight == 0
    assert actual_oi_underweight == 0


# TODO:
def test_oi_after_funding_when_longs_outweigh_shorts(market, feed, rando):
    pass


# TODO:
def test_oi_after_funding_when_shorts_are_zero(market, feed, rando):
    pass


# TODO:
def test_oi_after_funding_when_longs_are_zero(market, feed, rando):
    pass
