from brownie import chain


def test_latest_updates_data_on_first_call_for_quanto_feed(pool_daiweth_30bps,
                                                           pool_uniweth_30bps,
                                                           quanto_feed):
    micro_window = quanto_feed.microWindow()
    macro_window = quanto_feed.macroWindow()
    market_base_amount = quanto_feed.marketBaseAmount()
    market_base_token = quanto_feed.marketBaseToken()
    market_quote_token = quanto_feed.marketQuoteToken()
    timestamp = chain[-1]['timestamp']

    actual = quanto_feed.latest()

    # calculate the avg tick and liquidity values from pool.observe cumulatives
    # NOTE: consult() tested in test_integration.py
    seconds_agos = [macro_window, micro_window, 0]
    market_avg_ticks, market_avg_liqs = quanto_feed.consult(
        pool_daiweth_30bps, seconds_agos)
    ovlweth_avg_ticks, ovlweth_avg_liqs = quanto_feed.consult(
        pool_uniweth_30bps, seconds_agos)

    prices = []
    reserves = []
    has_reserve = True
    for i in range(2):
        # NOTE: getQuoteAtTick(), getReserveInOvl() tested in test_views.py
        price = quanto_feed.getQuoteAtTick(
            market_avg_ticks[i], market_base_amount,
            market_base_token, market_quote_token)
        reserve = quanto_feed.getReserveInOvl(
            market_avg_ticks[i], market_avg_liqs[i], ovlweth_avg_ticks[i])

        prices.append(price)
        reserves.append(reserve)

    expect = (timestamp, micro_window, macro_window, prices[1], prices[0],
              reserves[1], reserves[0], has_reserve)

    assert expect == actual


def test_latest_updates_data_on_first_call_for_inverse_feed(pool_uniweth_30bps,
                                                            inverse_feed):
    micro_window = inverse_feed.microWindow()
    macro_window = inverse_feed.macroWindow()
    market_base_amount = inverse_feed.marketBaseAmount()
    market_base_token = inverse_feed.marketBaseToken()
    market_quote_token = inverse_feed.marketQuoteToken()
    timestamp = chain[-1]['timestamp']

    actual = inverse_feed.latest()

    # calculate the avg tick and liquidity values from pool.observe cumulatives
    # NOTE: consult() tested in test_integration.py
    seconds_agos = [macro_window, micro_window, 0]
    market_avg_ticks, market_avg_liqs = inverse_feed.consult(
        pool_uniweth_30bps, seconds_agos)
    ovlweth_avg_ticks, ovlweth_avg_liqs = inverse_feed.consult(
        pool_uniweth_30bps, seconds_agos)

    prices = []
    reserves = []
    has_reserve = True
    for i in range(2):
        # NOTE: getQuoteAtTick(), getReserveInOvl() tested in test_views.py
        price = inverse_feed.getQuoteAtTick(
            market_avg_ticks[i], market_base_amount,
            market_base_token, market_quote_token)
        reserve = inverse_feed.getReserveInOvl(
            market_avg_ticks[i], market_avg_liqs[i], ovlweth_avg_ticks[i])

        prices.append(price)
        reserves.append(reserve)

    expect = (timestamp, micro_window, macro_window, prices[1], prices[0],
              reserves[1], reserves[0], has_reserve)

    assert expect == actual


def test_latest_updates_data_on_many_calls_for_quanto_feed(pool_daiweth_30bps,
                                                           pool_uniweth_30bps,
                                                           quanto_feed):
    micro_window = quanto_feed.microWindow()
    macro_window = quanto_feed.macroWindow()
    market_base_amount = quanto_feed.marketBaseAmount()
    market_base_token = quanto_feed.marketBaseToken()
    market_quote_token = quanto_feed.marketQuoteToken()

    # fetch from feed 3 times in a row w 60s in between
    for i in range(3):
        chain.mine(timedelta=60)
        timestamp = chain[-1]['timestamp']
        actual = quanto_feed.latest()

        # calculate the avg tick and liquidity values from pool.observe
        # cumulatives. NOTE: consult() tested in test_integration.py
        seconds_agos = [macro_window, micro_window, 0]
        market_avg_ticks, market_avg_liqs = quanto_feed.consult(
            pool_daiweth_30bps, seconds_agos)
        ovlweth_avg_ticks, ovlweth_avg_liqs = quanto_feed.consult(
            pool_uniweth_30bps, seconds_agos)

        prices = []
        reserves = []
        has_reserve = True
        for i in range(2):
            # NOTE: getQuoteAtTick(), getReserveInOvl() tested in test_views.py
            price = quanto_feed.getQuoteAtTick(
                market_avg_ticks[i], market_base_amount,
                market_base_token, market_quote_token)
            reserve = quanto_feed.getReserveInOvl(
                market_avg_ticks[i], market_avg_liqs[i], ovlweth_avg_ticks[i])

            prices.append(price)
            reserves.append(reserve)

        expect = (timestamp, micro_window, macro_window, prices[1], prices[0],
                  reserves[1], reserves[0], has_reserve)
        assert expect == actual


def test_latest_updates_data_on_many_calls_for_inverse_feed(pool_uniweth_30bps,
                                                            inverse_feed):
    micro_window = inverse_feed.microWindow()
    macro_window = inverse_feed.macroWindow()
    market_base_amount = inverse_feed.marketBaseAmount()
    market_base_token = inverse_feed.marketBaseToken()
    market_quote_token = inverse_feed.marketQuoteToken()

    # fetch from feed 3 times in a row w 60s in between
    for i in range(3):
        chain.mine(timedelta=60)
        timestamp = chain[-1]['timestamp']
        actual = inverse_feed.latest()

        # calculate the avg tick and liquidity values from pool.observe
        # cumulatives. NOTE: consult() tested in test_integration.py
        seconds_agos = [macro_window, micro_window, 0]
        market_avg_ticks, market_avg_liqs = inverse_feed.consult(
            pool_uniweth_30bps, seconds_agos)
        ovlweth_avg_ticks, ovlweth_avg_liqs = inverse_feed.consult(
            pool_uniweth_30bps, seconds_agos)

        prices = []
        reserves = []
        has_reserve = True
        for i in range(2):
            # NOTE: getQuoteAtTick(), getReserveInOvl() tested in test_views.py
            price = inverse_feed.getQuoteAtTick(
                market_avg_ticks[i], market_base_amount,
                market_base_token, market_quote_token)
            reserve = inverse_feed.getReserveInOvl(
                market_avg_ticks[i], market_avg_liqs[i], ovlweth_avg_ticks[i])

            prices.append(price)
            reserves.append(reserve)

        expect = (timestamp, micro_window, macro_window, prices[1], prices[0],
                  reserves[1], reserves[0], has_reserve)
        assert expect == actual
