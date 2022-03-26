import pytest
from brownie import (
    Contract, OverlayV1Token, OverlayV1Market, OverlayV1Factory,
    OverlayV1UniswapV3Feed, OverlayV1FeedMock, web3
)


@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts[0]


@pytest.fixture(scope="module")
def alice(accounts):
    yield accounts[1]


@pytest.fixture(scope="module")
def bob(accounts):
    yield accounts[2]


@pytest.fixture(scope="module")
def rando(accounts):
    yield accounts[3]


@pytest.fixture(scope="module")
def fee_recipient(accounts):
    yield accounts[4]


@pytest.fixture(scope="module")
def minter_role():
    yield web3.solidityKeccak(['string'], ["MINTER"])


@pytest.fixture(scope="module")
def burner_role():
    yield web3.solidityKeccak(['string'], ["BURNER"])


@pytest.fixture(scope="module")
def governor_role():
    yield web3.solidityKeccak(['string'], ["GOVERNOR"])


@pytest.fixture(scope="module", params=[8000000])
def create_token(gov, alice, bob, request):
    sup = request.param

    def create_token(supply=sup):
        tok = gov.deploy(OverlayV1Token)
        tok.mint(gov, supply * 10 ** tok.decimals(), {"from": gov})
        tok.transfer(alice, (supply/2) * 10 ** tok.decimals(), {"from": gov})
        tok.transfer(bob, (supply/2) * 10 ** tok.decimals(), {"from": gov})
        return tok

    yield create_token


@pytest.fixture(scope="module")
def ovl(create_token):
    yield create_token()


@pytest.fixture(scope="module")
def create_factory(gov, fee_recipient, request, ovl):
    def create_factory(tok=ovl, recipient=fee_recipient):
        # create the market factory
        # NOTE: Doesn't do anything in these market tests
        # NOTE: except return factory.feeRecipient()
        factory = gov.deploy(OverlayV1Factory, tok, recipient)
        return factory
    yield create_factory


@pytest.fixture(scope="module")
def factory(create_factory):
    yield create_factory()


@pytest.fixture(scope="module")
def dai():
    yield Contract.from_explorer("0x6B175474E89094C44Da98b954EedeAC495271d0F")


@pytest.fixture(scope="module")
def weth():
    yield Contract.from_explorer("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")


@pytest.fixture(scope="module")
def uni():
    # to be used as example ovl
    yield Contract.from_explorer("0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984")


@pytest.fixture(scope="module")
def pool_daiweth_30bps():
    yield Contract.from_explorer("0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8")


@pytest.fixture(scope="module")
def pool_uniweth_30bps():
    # to be used as example ovlweth pool
    yield Contract.from_explorer("0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801")


# TODO: params for different OverlayV1Feed types ... (to test BalancerV2
# and UniswapV3 in same test run)
@pytest.fixture(scope="module", params=[(600, 3600)])
def create_feed(gov, pool_daiweth_30bps, pool_uniweth_30bps, dai, weth,
                uni, request):
    micro, macro = request.param

    # ovlweth treated as uniweth for test purposes, feed ovl treated as uni
    mkt_pool = pool_daiweth_30bps.address
    oe_pool = pool_uniweth_30bps.address  # ovlweth => uniweth for testing
    tok = uni.address  # ovl => uni for testing
    mkt_base_tok = weth.address
    mkt_quote_tok = dai.address
    mkt_base_amt = 1 * 10 ** weth.decimals()

    def create_feed(market_pool=mkt_pool, ovlweth_pool=oe_pool, ovl=tok,
                    market_base_token=mkt_base_tok,
                    market_quote_token=mkt_quote_tok,
                    market_base_amount=mkt_base_amt, micro_window=micro,
                    macro_window=macro):
        feed = gov.deploy(OverlayV1UniswapV3Feed, market_pool, ovlweth_pool,
                          ovl, market_base_token, market_quote_token,
                          market_base_amount, micro_window, macro_window)
        return feed

    yield create_feed


@pytest.fixture(scope="module")
def feed(create_feed):
    yield create_feed()


# Mock feed to easily change price/reserve for testing of various conditions
@pytest.fixture(scope="module", params=[
    (600, 3600, 1000000000000000000, 2000000000000000000000000)
])
def create_mock_feed(gov, request):
    micro, macro, price, reserve = request.param

    def create_mock_feed(micro_window=micro, macro_window=macro, price=price,
                         reserve=reserve):
        mock_feed = gov.deploy(OverlayV1FeedMock, micro_window, macro_window,
                               price, reserve)
        return mock_feed

    yield create_mock_feed


@pytest.fixture(scope="module")
def mock_feed(create_mock_feed):
    yield create_mock_feed()


@pytest.fixture(scope="module", params=[(
    1220000000000,  # k
    500000000000000000,  # lmbda
    2500000000000000,  # delta
    5000000000000000000,  # capPayoff
    800000000000000000000000,  # capOi
    5000000000000000000,  # capLeverage
    2592000,  # circuitBreakerWindow
    66670000000000000000000,  # circuitBreakerMintTarget
    100000000000000000,  # maintenanceMargin
    100000000000000000,  # maintenanceMarginBurnRate
    10000000000000000,  # liquidationFeeRate
    750000000000000,  # tradingFeeRate
    100000000000000,  # minCollateral
    25000000000000,  # priceDriftUpperLimit
)])
def mock_market(gov, mock_feed, factory, ovl, create_market, request):
    risk_params = request.param
    yield create_market(feed=mock_feed, factory=factory,
                        risk_params=risk_params, governance=gov, ovl=ovl)


@pytest.fixture(scope="module")
def create_market(gov, ovl, minter_role, burner_role):
    def create_market(feed, factory, risk_params, governance=gov, ovl=ovl):
        market = governance.deploy(OverlayV1Market, ovl, feed, factory,
                                   risk_params)
        ovl.grantRole(minter_role, market, {"from": governance})
        ovl.grantRole(burner_role, market, {"from": governance})
        return market

    yield create_market


@pytest.fixture(scope="module", params=[(
    1220000000000,  # k
    500000000000000000,  # lmbda
    2500000000000000,  # delta
    5000000000000000000,  # capPayoff
    800000000000000000000000,  # capNotional
    5000000000000000000,  # capLeverage
    2592000,  # circuitBreakerWindow
    66670000000000000000000,  # circuitBreakerMintTarget
    100000000000000000,  # maintenanceMarginFraction
    100000000000000000,  # maintenanceMarginBurnRate
    10000000000000000,  # liquidationFeeRate
    750000000000000,  # tradingFeeRate
    100000000000000,  # minCollateral
    25000000000000,  # priceDriftUpperLimit
)])
def market(gov, feed, factory, ovl, create_market, request):
    risk_params = request.param
    yield create_market(feed=feed, factory=factory, risk_params=risk_params,
                        governance=gov, ovl=ovl)
