import unittest
from overlay_management import OM 

class TestRiskParams(unittest.TestCase):

    def test_risk_param_order(self): #the order is important, so we test it
        risk_params = ["k", "lambda", "delta", "capPayoff", "capNotional", "capLeverage", "circuitBreakerWindow", "circuitBreakerMintTarget", "maintenanceMarginFraction", "maintenanceMarginBurnRate", "liquidationFeeRate", "tradingFeeRate", "minCollateral", "priceDriftUpperLimit", "averageBlockTime"]
        self.assertListEqual(OM.risk_params, risk_params)

    def test_all_feeds_all_parameters(self):
        afap = OM.get_all_feeds_all_parameters()
        ...

    def test_filter_by_network(self):

        chainlist = [OM.ARB_TEST, OM.ARB_MAIN]
        filtered = OM.filter_by_blockchain(chainlist)
        self.assertEqual(len(filtered['mcap1000'].keys()), 2)

        chainlist = [OM.ARB_TEST]
        filtered = OM.filter_by_blockchain(chainlist)
        self.assertEqual(len(filtered['mcap1000'].keys()), 1)



if __name__ == '__main__':
    unittest.main()
