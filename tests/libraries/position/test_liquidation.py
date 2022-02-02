def test_is_underwater(position):
    entry_price = 100000000000000000000  # 100
    oi = 10000000000000000000  # 10
    debt = 8000000000000000000  # 8
    liquidated = False

    tol = 1e-4  # 1 bps

    # check returns True when long is underwater
    is_long = True
    current_price = 80000000000000000000 * (1 - tol)  # 80 * (1-tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns False when long is not underwater
    is_long = True
    current_price = 80000000000000000000 * (1 + tol)  # 80 * (1+tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns True when short is underwater
    is_long = False
    current_price = 120000000000000000000 * (1 + tol)  # 120 * (1+tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns False when short is not underwater
    is_long = False
    current_price = 120000000000000000000 * (1 - tol)  # 120 * (1-tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual


def test_is_underwater_when_oi_zero(position):
    entry_price = 100000000000000000000  # 100
    current_price = 90000000000000000000  # 90
    oi = 0  # 0
    debt = 8000000000000000000  # 8
    liquidated = False

    # check returns True when long oi is zero and has debt
    is_long = True
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns True when short oi is zero and has debt
    is_long = False
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual


def test_is_underwater_when_leverage_one(position):
    entry_price = 100000000000000000000  # 100
    oi = 10000000000000000000  # 10
    debt = 0  # 0
    liquidated = False

    tol = 1e-4  # 1bps

    # check returns False when long leverage is 1
    is_long = True
    current_price = 75000000000000000000  # 75
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns False when short price moves less than 2x
    is_long = False
    current_price = 200000000000000000000 * (1 - tol)  # 200 * (1-tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual

    # check returns True when short price moves more than 2x
    is_long = False
    current_price = 200000000000000000000 * (1 + tol)  # 200 * (1+tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isUnderwater(pos, oi, oi, current_price)
    assert expect == actual


def test_is_liquidatable(position):
    entry_price = 100000000000000000000  # 100
    oi = 10000000000000000000  # 10
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = False

    tol = 1e-4  # 1 bps

    # liquidatable when position.value < maintenance * initial_oi
    # check returns True when long is liquidatable
    is_long = True
    current_price = 90000000000000000000 * (1 - tol)  # 90 * (1-tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns False when long is not liquidatable
    is_long = True
    current_price = 90000000000000000000 * (1 + tol)  # 90 * (1+tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns True when short is liquidatable
    is_long = False
    current_price = 110000000000000000000 * (1 + tol)  # 110 * (1+tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns False when short is not liquidatable
    is_long = False
    current_price = 110000000000000000000 * (1 - tol)  # 110 * (1-tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual


def test_is_liquidatable_when_oi_zero(position):
    entry_price = 100000000000000000000  # 100
    current_price = 90000000000000000000  # 90
    oi = 0  # 0
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = False

    # check returns False when long oi is zero
    is_long = True
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns False when short oi is zero
    is_long = False
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual


def test_is_liquidatable_when_liquidated(position):
    entry_price = 100000000000000000000  # 100
    current_price = 90000000000000000000  # 90
    oi = 0  # 0
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = True

    # check returns False when long oi is zero
    is_long = True
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns False when short oi is zero
    is_long = False
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual


def test_is_liquidatable_when_leverage_one(position):
    entry_price = 100000000000000000000  # 100
    oi = 10000000000000000000  # 10
    debt = 0  # 0
    maintenance = 100000000000000000  # 10%
    liquidated = False

    tol = 1e-4  # 1bps

    # check returns False when long price moves less than maintenance require
    is_long = True
    current_price = 10000000000000000000 * (1 + tol)  # 10 * (1+tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns True when long price moves more than maintenance require
    is_long = True
    current_price = 10000000000000000000 * (1 - tol)  # 10 * (1-tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns False when short price moves less than maintenance require
    is_long = False
    current_price = 190000000000000000000 * (1 - tol)  # 190 * (1-tol)
    expect = False
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual

    # check returns True when short price moves more than maintenance require
    is_long = False
    current_price = 190000000000000000000 * (1 + tol)  # 190 * (1+tol)
    expect = True
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.isLiquidatable(pos, oi, oi, current_price, maintenance)
    assert expect == actual


def test_liquidation_price(position):
    entry_price = 100000000000000000000  # 100
    oi = 10000000000000000000  # 10
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = False

    # liquidatable price occurs when position.value = maintenance * initial_oi
    # check returns correct liquidation price for long
    is_long = True
    expect = 90000000000000000000
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.liquidationPrice(pos, oi, oi, maintenance)
    assert expect == actual

    # check returns correct liquidation price for short
    is_long = False
    expect = 110000000000000000000
    pos = (oi, debt, is_long, liquidated, entry_price)
    actual = position.liquidationPrice(pos, oi, oi, maintenance)
    assert expect == actual


def test_liquidation_price_when_oi_zero(position):
    entry_price = 100000000000000000000  # 100
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = False
    is_long = True

    # check liqPrice is zero when posOiInitial is zero
    oi = 0
    total_oi = 100
    pos = (oi, debt, is_long, liquidated, entry_price)

    expect = 0
    actual = position.liquidationPrice(pos, total_oi, total_oi, maintenance)
    assert expect == actual

    # check liqPrice is zero when posOiCurrent is zero
    oi = 100
    total_oi = 0
    pos = (oi, debt, is_long, liquidated, entry_price)

    expect = 0
    actual = position.liquidationPrice(pos, total_oi, total_oi, maintenance)
    assert expect == actual


def test_liquidation_price_when_liquidated_is_true(position):
    entry_price = 100000000000000000000  # 100
    debt = 8000000000000000000  # 8
    maintenance = 100000000000000000  # 10%
    liquidated = True
    is_long = True

    # check liqPrice is zero when posOiInitial is zero
    oi = 100
    total_oi = 100
    pos = (oi, debt, is_long, liquidated, entry_price)

    expect = 0
    actual = position.liquidationPrice(pos, total_oi, total_oi, maintenance)
    assert expect == actual
