// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IOverlayV1Factory.sol";
import "./interfaces/IOverlayV1Market.sol";
import "./interfaces/IOverlayV1Token.sol";
import "./interfaces/feeds/IOverlayV1Feed.sol";
import "./interfaces/callback/IOverlayMarketLiquidateCallback.sol";

import "./libraries/FixedCast.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/Oracle.sol";
import "./libraries/Position.sol";
import "./libraries/Risk.sol";
import "./libraries/Roller.sol";
import "./libraries/Tick.sol";

contract OverlayV1Market is IOverlayV1Market, Pausable {
    using FixedCast for uint256;
    using FixedPoint for uint256;
    using Oracle for Oracle.Data;
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Risk for uint256[15];
    using Roller for Roller.Snapshot;

    // internal constants
    uint256 internal constant ONE = 1e18; // 18 decimal places
    uint256 internal constant TO_MS = 1e3; // convert seconds to milliseconds

    // cap for euler exponent powers; SEE: ./libraries/LogExpMath.sol::pow
    // using ~ 1/2 library max for substantial padding
    uint256 internal constant MAX_NATURAL_EXPONENT = 20e18;

    // immutables
    IOverlayV1Token public immutable ovl; // ovl token
    address public immutable feed; // oracle feed
    address public immutable factory; // factory that deployed this market

    // risk params
    uint256[15] public params; // params.idx order based on Risk.Parameters enum

    // aggregate oi quantities
    uint256 public oiLong;
    uint256 public oiShort;
    uint256 public oiLongShares;
    uint256 public oiShortShares;

    // rollers
    Roller.Snapshot public override snapshotVolumeBid; // snapshot of recent volume on bid
    Roller.Snapshot public override snapshotVolumeAsk; // snapshot of recent volume on ask
    Roller.Snapshot public override snapshotMinted; // snapshot of recent PnL minted/burned

    // positions
    mapping(bytes32 => Position.Info) public override positions;
    uint256 private _totalPositions;

    // data from last call to update
    uint256 public timestampUpdateLast;

    // cached risk calcs
    uint256 public dpUpperLimit; // e**(+priceDriftUpperLimit * macroWindow)

    // emergency shutdown
    bool public isShutdown;

    // factory modifier for governance sensitive functions
    modifier onlyFactory() {
        require(msg.sender == factory, "OVLV1: !factory");
        _;
    }

    // not shutdown modifier for regular functionality
    modifier notShutdown() {
        require(!isShutdown, "OVLV1: shutdown");
        _;
    }

    // shutdown modifier for emergencies
    modifier hasShutdown() {
        require(isShutdown, "OVLV1: !shutdown");
        _;
    }

    // events for core functions
    /// @param sender address that initiated build (owns position)
    /// @param positionId id of built position
    /// @param oi oi of position at build
    /// @param debt debt of position at build
    /// @param isLong whether is long or short
    /// @param price entry price
    /// @param oiAfterBuild oi after build
    /// @param oiSharesAfterBuild oi shares after build
    event Build(
        address indexed sender,
        uint256 positionId,
        uint256 oi,
        uint256 debt,
        bool isLong,
        uint256 price,
        uint256 oiAfterBuild,
        uint256 oiSharesAfterBuild
    );

    /// @param sender address that initiated unwind (owns position)
    /// @param positionId id of unwound position
    /// @param fraction fraction of position unwound
    /// @param mint total amount minted (+/-) at unwind
    /// @param price exit price
    /// @param oiAfterUnwind oi after unwind
    /// @param oiSharesAfterUnwind oi shares after unwind
    event Unwind(
        address indexed sender,
        uint256 positionId,
        uint256 fraction,
        int256 mint,
        uint256 price,
        uint256 oiAfterUnwind,
        uint256 oiSharesAfterUnwind
    );

    /// @param sender address that initiated liquidate
    /// @param owner address that owned the liquidated position
    /// @param positionId id of the liquidated position
    /// @param mint total amount burned (-) at liquidate
    /// @param price liquidation price
    /// @param oiAfterLiquidate oi after liquidate
    /// @param oiSharesAfterLiquidate oi shares after liquidate
    event Liquidate(
        address indexed sender,
        address indexed owner,
        uint256 positionId,
        int256 mint,
        uint256 price,
        uint256 oiAfterLiquidate,
        uint256 oiSharesAfterLiquidate
    );

    /// @param sender address that initiated withdraw (owns position)
    /// @param positionId id of withdrawn position
    /// @param collateral total amount of collateral withdrawn
    event EmergencyWithdraw(address indexed sender, uint256 positionId, uint256 collateral);

    /// @param newDpUpperLimit new value for dpUpperLimit
    event CacheRiskCalc(uint256 newDpUpperLimit);

    /// @param oiLong oiLong after public update
    /// @param oiShort oiShort after public update
    event Update(uint256 oiLong, uint256 oiShort);

    event LiquidateCallbackFailed(address owner, uint256 positionId);

    constructor() {
        (address _ovl, address _feed, address _factory) =
            IOverlayV1Deployer(msg.sender).parameters();
        ovl = IOverlayV1Token(_ovl);
        feed = _feed;
        factory = _factory;
    }

    /// @notice initializes the market and its risk params
    /// @notice called only once by factory on deployment
    function initialize(uint256[15] memory _params) external onlyFactory {
        // initialize update data
        Oracle.Data memory data = IOverlayV1Feed(feed).latest();
        require(_midFromFeed(data) > 0, "OVLV1:!data");
        timestampUpdateLast = block.timestamp;

        // check risk params valid
        uint256 _capLeverage = _params[uint256(Risk.Parameters.CapLeverage)];
        uint256 _delta = _params[uint256(Risk.Parameters.Delta)];
        uint256 _maintenanceMarginFraction =
            _params[uint256(Risk.Parameters.MaintenanceMarginFraction)];
        uint256 _liquidationFeeRate = _params[uint256(Risk.Parameters.LiquidationFeeRate)];
        require(
            _capLeverage
                <= ONE.divDown(
                    2 * _delta + _maintenanceMarginFraction.divDown(ONE - _liquidationFeeRate)
                ),
            "OVLV1: max lev immediately liquidatable"
        );

        uint256 _priceDriftUpperLimit = _params[uint256(Risk.Parameters.PriceDriftUpperLimit)];
        require(
            _priceDriftUpperLimit * data.macroWindow < MAX_NATURAL_EXPONENT,
            "OVLV1: price drift exceeds max exp"
        );
        _cacheRiskCalc(Risk.Parameters.PriceDriftUpperLimit, _priceDriftUpperLimit);

        // set the risk params
        for (uint256 i = 0; i < _params.length; i++) {
            params[i] = _params[i];
        }
    }

    /// @dev builds a new position
    function build(uint256 collateral, uint256 leverage, bool isLong, uint256 priceLimit)
        external
        notShutdown
        returns (uint256 positionId_)
    {
        require(leverage >= ONE, "OVLV1:lev<min");
        require(leverage <= params.get(Risk.Parameters.CapLeverage), "OVLV1:lev>max");
        require(collateral >= params.get(Risk.Parameters.MinCollateral), "OVLV1:collateral<min");

        uint256 oi;
        uint256 debt;
        uint256 price;
        uint256 tradingFee;
        // avoids stack too deep
        {
            // call to update before any effects
            Oracle.Data memory data = update();

            // calculate notional, oi, and trading fees. fees charged on notional
            // and added to collateral transferred in
            uint256 notional = collateral.mulUp(leverage);
            uint256 midPrice = _midFromFeed(data);
            oi = oiFromNotional(notional, midPrice);

            // check have more than zero number of contracts built
            require(oi > 0, "OVLV1:oi==0");

            // calculate debt and trading fees. fees charged on notional
            // and added to collateral transferred in
            debt = notional - collateral;
            tradingFee = notional.mulUp(params.get(Risk.Parameters.TradingFeeRate));

            // calculate current notional cap adjusted for front run
            // and back run bounds. transform into a cap on open interest
            uint256 capOi = oiFromNotional(
                capNotionalAdjustedForBounds(data, params.get(Risk.Parameters.CapNotional)),
                midPrice
            );

            // longs get the ask and shorts get the bid on build
            // register the additional volume on either the ask or bid
            // where volume = oi / capOi
            price = isLong
                ? ask(data, _registerVolumeAsk(data, oi, capOi))
                : bid(data, _registerVolumeBid(data, oi, capOi));
            // check price hasn't changed more than max slippage specified by trader
            require(isLong ? price <= priceLimit : price >= priceLimit, "OVLV1:slippage>max");

            // add new position's open interest to the side's aggregate oi value
            // and increase number of oi shares issued
            uint256 oiShares = _addToOiAggregates(oi, capOi, isLong);

            // assemble position info data
            // check position is not immediately liquidatable prior to storing
            Position.Info memory pos = Position.Info({
                notionalInitial: uint96(notional), // won't overflow as capNotional max is 8e24
                debtInitial: uint96(debt),
                midTick: Tick.priceToTick(midPrice),
                entryTick: Tick.priceToTick(price),
                isLong: isLong,
                liquidated: false,
                oiShares: uint240(oiShares), // won't overflow as oiShares ~ notional/mid
                fractionRemaining: ONE.toUint16Fixed()
            });
            require(
                /// @param midPrice mid price used on liquidations
                !pos.liquidatable(
                    isLong ? oiLong : oiShort,
                    isLong ? oiLongShares : oiShortShares,
                    midPrice,
                    params.get(Risk.Parameters.CapPayoff),
                    params.get(Risk.Parameters.MaintenanceMarginFraction),
                    params.get(Risk.Parameters.LiquidationFeeRate)
                ),
                "OVLV1:liquidatable"
            );

            // store the position info data
            positionId_ = _totalPositions;
            positions.set(msg.sender, positionId_, pos);
            _totalPositions++;
        }

        // emit build event
        emit Build(
            msg.sender,
            positionId_,
            oi,
            debt,
            isLong,
            price,
            isLong ? oiLong : oiShort,
            isLong ? oiLongShares : oiShortShares
        );

        // transfer in the OVL collateral needed to back the position + fees
        // trading fees charged as a percentage on notional size of position
        ovl.transferFrom(msg.sender, address(this), collateral + tradingFee);

        // send trading fees to trading fee recipient
        ovl.transfer(IOverlayV1Factory(factory).feeRecipient(), tradingFee);
    }

    /// @dev unwinds fraction of an existing position
    function unwind(uint256 positionId, uint256 fraction, uint256 priceLimit)
        external
        notShutdown
    {
        require(fraction <= ONE, "OVLV1:fraction>max");
        // only keep 4 decimal precision (1 bps) for fraction given
        // pos.fractionRemaining only to 4 decimals
        fraction -= fraction % 1e14;
        require(fraction > 0, "OVLV1:fraction<min");

        uint256 value;
        uint256 cost;
        uint256 price;
        uint256 tradingFee;
        Position.Info memory pos;
        // avoids stack too deep
        {
            // call to update before any effects
            Oracle.Data memory data = update();

            // check position exists
            pos = positions.get(msg.sender, positionId);
            require(pos.exists(), "OVLV1:!position");

            // cache for gas savings
            uint256 oiTotalOnSide = pos.isLong ? oiLong : oiShort;
            uint256 oiTotalSharesOnSide = pos.isLong ? oiLongShares : oiShortShares;

            // check position not liquidatable otherwise can't unwind
            require(
                /// @param midPrice mid price used on liquidations
                !pos.liquidatable(
                    oiTotalOnSide,
                    oiTotalSharesOnSide,
                    _midFromFeed(data),
                    params.get(Risk.Parameters.CapPayoff),
                    params.get(Risk.Parameters.MaintenanceMarginFraction),
                    params.get(Risk.Parameters.LiquidationFeeRate)
                ),
                "OVLV1:liquidatable"
            );

            // longs get the bid and shorts get the ask on unwind
            // register the additional volume on either the ask or bid
            // where volume = oi / capOi
            // current cap only adjusted for bounds (no circuit breaker so traders
            // don't get stuck in a position)
            uint256 capOi = oiFromNotional(
                capNotionalAdjustedForBounds(data, params.get(Risk.Parameters.CapNotional)),
                _midFromFeed(data)
            );
            price = pos.isLong
                ? bid(
                    data,
                    _registerVolumeBid(
                        data, pos.oiCurrent(fraction, oiTotalOnSide, oiTotalSharesOnSide), capOi
                    )
                )
                : ask(
                    data,
                    _registerVolumeAsk(
                        data, pos.oiCurrent(fraction, oiTotalOnSide, oiTotalSharesOnSide), capOi
                    )
                );
            // check price hasn't changed more than max slippage specified by trader
            require(pos.isLong ? price >= priceLimit : price <= priceLimit, "OVLV1:slippage>max");

            // calculate the value and cost of the position for pnl determinations
            // and amount to transfer
            uint256 capPayoff = params.get(Risk.Parameters.CapPayoff);
            value = pos.value(fraction, oiTotalOnSide, oiTotalSharesOnSide, price, capPayoff);
            cost = pos.cost(fraction);

            // calculate the trading fee as % on notional
            uint256 tradingFeeRate = params.get(Risk.Parameters.TradingFeeRate);
            tradingFee = pos.tradingFee(
                fraction, oiTotalOnSide, oiTotalSharesOnSide, price, capPayoff, tradingFeeRate
            );
            tradingFee = Math.min(tradingFee, value); // if value < tradingFee

            // subtract unwound open interest from the side's aggregate oi value
            // and decrease number of oi shares issued
            _reduceOIAndOIShares(pos, fraction);

            // register the amount to be minted/burned
            // capPayoff prevents overflow reverts with int256 cast
            _registerMintOrBurn(int256(value) - int256(cost));

            // store the updated position info data by reducing the
            // oiShares and fraction remaining of initial position
            pos.oiShares -= uint240(pos.oiSharesCurrent(fraction));
            pos.fractionRemaining = pos.updatedFractionRemaining(fraction);
            // ensure there are no dead shares left
            if (pos.fractionRemaining == 0 && pos.oiShares > 0) {
                _reduceOIAndOIShares(pos, ONE);
                pos.oiShares = 0;
            }
            positions.set(msg.sender, positionId, pos);
        }

        // emit unwind event
        emit Unwind(
            msg.sender,
            positionId,
            fraction,
            int256(value) - int256(cost),
            price,
            pos.isLong ? oiLong : oiShort,
            pos.isLong ? oiLongShares : oiShortShares
        );

        // mint or burn the pnl for the position
        if (value >= cost) {
            ovl.mint(address(this), value - cost);
        } else {
            ovl.burn(cost - value);
        }

        // transfer out the unwound position value less fees to trader
        ovl.transfer(msg.sender, value - tradingFee);

        // send trading fees to trading fee recipient
        ovl.transfer(IOverlayV1Factory(factory).feeRecipient(), tradingFee);
    }

    /// @dev liquidates a liquidatable position
    function liquidate(address owner, uint256 positionId) external notShutdown {
        uint256 value;
        uint256 cost;
        uint256 price;
        uint256 liquidationFee;
        uint256 marginToBurn;
        uint256 marginRemaining;
        Position.Info memory pos;

        // if the owner of the potision has LIQUIDATE_CALLBACK_ROLE, make a callback
        // must be executed before the new postion state is stored
        // attempt the callback without reverting on failure
        if (ovl.hasRole(LIQUIDATE_CALLBACK_ROLE, owner)) {
            try IOverlayMarketLiquidateCallback(owner).overlayMarketLiquidateCallback(positionId) {}
            catch {
                emit LiquidateCallbackFailed(owner, positionId);
            }
        }

        // avoids stack too deep
        {
            // check position exists
            pos = positions.get(owner, positionId);
            require(pos.exists(), "OVLV1:!position");

            // call to update before any effects
            Oracle.Data memory data = update();

            // cache for gas savings
            uint256 oiTotalOnSide = pos.isLong ? oiLong : oiShort;
            uint256 oiTotalSharesOnSide = pos.isLong ? oiLongShares : oiShortShares;
            uint256 capPayoff = params.get(Risk.Parameters.CapPayoff);

            // entire position should be liquidated
            uint256 fraction = ONE;

            // Use mid price without volume for liquidation (oracle price effectively) to
            // prevent market impact manipulation from causing unneccessary liquidations
            price = _midFromFeed(data);

            // check position is liquidatable
            require(
                pos.liquidatable(
                    oiTotalOnSide,
                    oiTotalSharesOnSide,
                    price,
                    capPayoff,
                    params.get(Risk.Parameters.MaintenanceMarginFraction),
                    params.get(Risk.Parameters.LiquidationFeeRate)
                ),
                "OVLV1:!liquidatable"
            );

            // calculate the value and cost of the position for pnl determinations
            // and amount to transfer
            value = pos.value(fraction, oiTotalOnSide, oiTotalSharesOnSide, price, capPayoff);
            cost = pos.cost(fraction);

            // calculate the liquidation fee as % on remaining value
            // sent as reward to liquidator
            liquidationFee = value.mulDown(params.get(Risk.Parameters.LiquidationFeeRate));
            marginRemaining = value - liquidationFee;

            // Reduce burn amount further by the mm burn rate, as insurance
            // for cases when not liquidated in time
            marginToBurn =
                marginRemaining.mulDown(params.get(Risk.Parameters.MaintenanceMarginBurnRate));
            marginRemaining -= marginToBurn;

            // subtract liquidated open interest from the side's aggregate oi value
            // and decrease number of oi shares issued
            _reduceOIAndOIShares(pos, fraction);

            // register the amount to be burned
            _registerMintOrBurn(int256(value) - int256(cost) - int256(marginToBurn));

            // store the updated position info data. mark as liquidated
            pos.liquidated = true;
            pos.oiShares = 0;
            pos.fractionRemaining = 0;
            positions.set(owner, positionId, pos);
        }

        // emit liquidate event
        emit Liquidate(
            msg.sender,
            owner,
            positionId,
            int256(value) - int256(cost) - int256(marginToBurn),
            price,
            pos.isLong ? oiLong : oiShort,
            pos.isLong ? oiLongShares : oiShortShares
        );

        // burn the pnl for the position + insurance margin
        ovl.burn(cost - value + marginToBurn);

        // transfer out the liquidation fee to liquidator for reward
        ovl.transfer(msg.sender, liquidationFee);

        // send remaining margin to trading fee recipient
        ovl.transfer(IOverlayV1Factory(factory).feeRecipient(), marginRemaining);
    }

    /// @dev updates market: pays funding and fetches freshest data from feed
    /// @dev update is called every time market is interacted with
    function update() public whenNotPaused returns (Oracle.Data memory) {
        // pay funding for time elasped since last interaction w market
        _payFunding();

        // check Arbitrum sequencer is up and grace period has
        // passed before fetching new data from feed
        require(IOverlayV1Factory(factory).isUpAndGracePeriodPassed(), "OVLV1:!sequencer");

        // fetch new oracle data from feed
        // applies sanity check in case of data manipulation
        Oracle.Data memory data = IOverlayV1Feed(feed).latest();
        require(dataIsValid(data), "OVLV1:!data");

        emit Update(oiLong, oiShort);
        // return the latest data from feed
        return data;
    }

    /// @dev sanity check on data fetched from oracle in case of manipulation
    /// @dev rough check that log price bounded by +/- priceDriftUpperLimit * dt
    /// @dev when comparing priceMacro(now) vs priceMacro(now - macroWindow)
    function dataIsValid(Oracle.Data memory data) public view returns (bool) {
        // upper and lower limits are e**(+/- priceDriftUpperLimit * dt)
        uint256 _dpUpperLimit = dpUpperLimit;
        uint256 _dpLowerLimit = ONE.divDown(_dpUpperLimit);

        // compare current price over macro window vs price over macro window
        // one macro window in the past
        uint256 priceNow = data.priceOverMacroWindow;
        uint256 priceLast = data.priceOneMacroWindowAgo;
        if (priceLast == 0 || priceNow == 0) {
            // data is not valid if price is zero
            return false;
        }

        // price is valid if within upper and lower limits on drift given
        // time elapsed over one macro window
        uint256 dp = priceNow.divUp(priceLast);
        return (dp >= _dpLowerLimit && dp <= _dpUpperLimit);
    }

    /// @notice Current open interest after funding payments transferred
    /// @notice from overweight oi side to underweight oi side
    /// @return New rebalanced (oiOverweight, oiUnderweight) after funding payments
    /// @dev The value of oiOverweight must be >= oiUnderweight
    /// @dev The oiOverweight returned will be <= the oiOverweight passed in.
    /// @dev The oiUnderweight returned will be >= the oiUnderweight passed in.
    /// For further reference see Section II (Funding Payments) of the whitepaper.
    function oiAfterFunding(uint256 oiOverweight, uint256 oiUnderweight, uint256 timeElapsed)
        public
        view
        returns (uint256, uint256)
    {
        uint256 oiTotal = oiOverweight + oiUnderweight;
        uint256 oiImbalance = oiOverweight - oiUnderweight;

        // This invariant must hold after updating both oiOverweight and oiUnderweight
        uint256 oiInvariant = oiUnderweight * oiOverweight;

        // If no OI or imbalance, no funding occurs. Handles div by zero case below
        if (oiTotal == 0 || oiImbalance == 0) {
            return (oiOverweight, oiUnderweight);
        }

        // draw down the imbalance by factor of e**(-2*k*t)
        // but min to zero if pow = 2*k*t exceeds MAX_NATURAL_EXPONENT
        uint256 fundingFactor;
        uint256 pow = 2 * params.get(Risk.Parameters.K) * timeElapsed;
        if (pow < MAX_NATURAL_EXPONENT) {
            fundingFactor = ONE.divDown(pow.expUp()); // e**(-pow)
        }

        // Decrease total aggregate open interest (i.e. oiLong + oiShort)
        // to compensate protocol for pro-rata share of imbalance liability
        // OI_tot(t) = OI_tot(0) * \
        //  sqrt( 1 - (OI_imb(0)/OI_tot(0))**2 * (1 - e**(-4*k*t)) )

        // Guaranteed 0 <= underRoot <= 1
        uint256 oiImbFraction = oiImbalance.divDown(oiTotal);
        uint256 underRoot = ONE
            - oiImbFraction.mulDown(oiImbFraction).mulDown(ONE - fundingFactor.mulDown(fundingFactor));

        // oiTotalNow guaranteed <= oiTotalBefore (burn happens)
        oiTotal = oiTotal.mulDown(underRoot.powDown(ONE / 2));

        // Time decay imbalance: OI_imb(t) = OI_imb(0) * e**(-2*k*t)
        // oiImbalanceNow guaranteed <= oiImbalanceBefore
        oiImbalance = oiImbalance.mulDown(fundingFactor);

        // overweight pays underweight
        // use oiOver * oiUnder = invariant for oiUnderNow to avoid any
        // potential overflow reverts
        oiOverweight = (oiTotal + oiImbalance) / 2;
        if (oiOverweight != 0) {
            // oiUnderweight = oiInvariant / oiOverweight, rounding up
            oiUnderweight = oiInvariant == 0 ? 0 : (oiInvariant - 1) / oiOverweight + 1;
        }
        return (oiOverweight, oiUnderweight);
    }

    /// @dev current oi cap with adjustments to lower in the event
    /// @dev market has printed a lot in recent past
    function capOiAdjustedForCircuitBreaker(uint256 cap) public view returns (uint256) {
        // Adjust cap downward for circuit breaker. Use snapshotMinted
        // but transformed to account for decay in magnitude of minted since
        // last snapshot taken
        Roller.Snapshot memory snapshot = snapshotMinted;
        uint256 circuitBreakerWindow = params.get(Risk.Parameters.CircuitBreakerWindow);
        snapshot = snapshot.transform(block.timestamp, circuitBreakerWindow, 0);
        cap = circuitBreaker(snapshot, cap);
        return cap;
    }

    /// @dev bound on oi cap from circuit breaker
    /// @dev Three cases:
    /// @dev 1. minted < 1x target amount over circuitBreakerWindow: return cap
    /// @dev 2. minted > 2x target amount over last circuitBreakerWindow: return 0
    /// @dev 3. minted between 1x and 2x target amount: return cap * (2 - minted/target)
    function circuitBreaker(Roller.Snapshot memory snapshot, uint256 cap)
        public
        view
        returns (uint256)
    {
        int256 minted = int256(snapshot.cumulative());
        uint256 circuitBreakerMintTarget = params.get(Risk.Parameters.CircuitBreakerMintTarget);
        if (minted <= int256(circuitBreakerMintTarget)) {
            return cap;
        } else if (minted >= 2 * int256(circuitBreakerMintTarget)) {
            return 0;
        }

        // case 3 (circuit breaker adjustment downward)
        uint256 adjustment = 2 * ONE - uint256(minted).divDown(circuitBreakerMintTarget);
        return cap.mulDown(adjustment);
    }

    /// @dev current notional cap with adjustments to prevent
    /// @dev front-running trade and back-running trade
    function capNotionalAdjustedForBounds(Oracle.Data memory data, uint256 cap)
        public
        view
        returns (uint256)
    {
        if (data.hasReserve) {
            // Adjust cap downward if exceeds bounds from front run attack
            cap = Math.min(cap, frontRunBound(data));

            // Adjust cap downward if exceeds bounds from back run attack
            cap = Math.min(cap, backRunBound(data));
        }
        return cap;
    }

    /// @dev bound on notional cap to mitigate front-running attack
    /// @dev bound = lmbda * reserveInOvl
    function frontRunBound(Oracle.Data memory data) public view returns (uint256) {
        uint256 lmbda = params.get(Risk.Parameters.Lmbda);
        return lmbda.mulDown(data.reserveOverMicroWindow);
    }

    /// @dev bound on notional cap to mitigate back-running attack
    /// @dev bound = macroWindowInBlocks * reserveInOvl * 2 * delta
    function backRunBound(Oracle.Data memory data) public view returns (uint256) {
        uint256 averageBlockTime = params.get(Risk.Parameters.AverageBlockTime);
        uint256 window = (data.macroWindow * ONE * TO_MS) / averageBlockTime;
        uint256 delta = params.get(Risk.Parameters.Delta);
        return delta.mulDown(data.reserveOverMicroWindow).mulDown(window).mulDown(2 * ONE);
    }

    /// @dev Returns the open interest in number of contracts for a given notional
    /// @dev Uses _midFromFeed(data) price to calculate oi: OI = Q / P
    function oiFromNotional(uint256 notional, uint256 midPrice) public pure returns (uint256) {
        return notional.divDown(midPrice);
    }

    /// @dev bid price given oracle data and recent volume
    function bid(Oracle.Data memory data, uint256 volume) public view returns (uint256 bid_) {
        bid_ = Math.min(data.priceOverMicroWindow, data.priceOverMacroWindow);

        // add static spread (delta) and market impact (lmbda * volume)
        uint256 delta = params.get(Risk.Parameters.Delta);
        uint256 lmbda = params.get(Risk.Parameters.Lmbda);
        uint256 pow = delta + lmbda.mulUp(volume);
        require(pow < MAX_NATURAL_EXPONENT, "OVLV1:slippage>max");

        bid_ = bid_.mulDown(ONE.divDown(pow.expUp())); // bid * e**(-pow)
    }

    /// @dev ask price given oracle data and recent volume
    function ask(Oracle.Data memory data, uint256 volume) public view returns (uint256 ask_) {
        ask_ = Math.max(data.priceOverMicroWindow, data.priceOverMacroWindow);

        // add static spread (delta) and market impact (lmbda * volume)
        uint256 delta = params.get(Risk.Parameters.Delta);
        uint256 lmbda = params.get(Risk.Parameters.Lmbda);
        uint256 pow = delta + lmbda.mulUp(volume);
        require(pow < MAX_NATURAL_EXPONENT, "OVLV1:slippage>max");

        ask_ = ask_.mulUp(pow.expUp()); // ask * e**(pow)
    }

    /// @dev mid price without impact/spread given oracle data and recent volume
    /// @dev used for gas savings to avoid accessing storage for delta, lmbda
    function _midFromFeed(Oracle.Data memory data) private pure returns (uint256 mid_) {
        mid_ = Math.average(data.priceOverMicroWindow, data.priceOverMacroWindow);
    }

    /// @dev Rolling volume adjustments on bid side to be used for market impact.
    /// @dev Volume values are normalized with respect to cap
    function _registerVolumeBid(Oracle.Data memory data, uint256 volume, uint256 cap)
        private
        returns (uint256)
    {
        // save gas with snapshot in memory
        Roller.Snapshot memory snapshot = snapshotVolumeBid;
        int256 value = int256(volume.divUp(cap));

        // calculates the decay in the rolling volume since last snapshot
        // and determines new window to decay over
        snapshot = snapshot.transform(block.timestamp, data.microWindow, value);

        // store the transformed snapshot
        snapshotVolumeBid = snapshot;

        // return the cumulative volume
        return uint256(snapshot.cumulative());
    }

    /// @dev Rolling volume adjustments on ask side to be used for market impact.
    /// @dev Volume values are normalized with respect to cap
    function _registerVolumeAsk(Oracle.Data memory data, uint256 volume, uint256 cap)
        private
        returns (uint256)
    {
        // save gas with snapshot in memory
        Roller.Snapshot memory snapshot = snapshotVolumeAsk;
        int256 value = int256(volume.divUp(cap));

        // calculates the decay in the rolling volume since last snapshot
        // and determines new window to decay over
        snapshot = snapshot.transform(block.timestamp, data.microWindow, value);

        // store the transformed snapshot
        snapshotVolumeAsk = snapshot;

        // return the cumulative volume
        return uint256(snapshot.cumulative());
    }

    /// @notice Rolling mint accumulator to be used for circuit breaker
    /// @dev value > 0 registers a mint, value <= 0 registers a burn
    function _registerMintOrBurn(int256 value) private returns (int256) {
        // save gas with snapshot in memory
        Roller.Snapshot memory snapshot = snapshotMinted;

        // calculates the decay in the rolling amount minted since last snapshot
        // and determines new window to decay over
        uint256 circuitBreakerWindow = params.get(Risk.Parameters.CircuitBreakerWindow);
        snapshot = snapshot.transform(block.timestamp, circuitBreakerWindow, value);

        // store the transformed snapshot
        snapshotMinted = snapshot;

        // return the cumulative mint amount
        int256 minted = snapshot.cumulative();
        return minted;
    }

    /// @notice subtract open interest from the side's aggregate oi value
    /// @notice and decrease number of oi shares issued
    function _reduceOIAndOIShares(Position.Info memory pos, uint256 fraction) internal {
        // NOTE: use subFloor to avoid reverts with oi rounding issues
        if (pos.isLong) {
            oiLong = oiLong.subFloor(pos.oiCurrent(fraction, oiLong, oiLongShares));
            oiLongShares -= pos.oiSharesCurrent(fraction);
        } else {
            oiShort = oiShort.subFloor(pos.oiCurrent(fraction, oiShort, oiShortShares));
            oiShortShares -= pos.oiSharesCurrent(fraction);
        }
    }

    /// @notice Updates the market for funding changes to open interest (oi)
    /// since last time market was interacted with.
    /// @dev Funding payments are used to decrease open interest imbalance over time.
    /// @dev Rebalances oiLong and oiShort:
    /// If oiLong > oiShort, then oiLong pays funding to oiShort (ie. oiLong decreases and oiShort increases)
    /// If oiShort > oiLong, then oiShort pays funding to oiLong (ie. oiShort decreases and oiLong increases)
    function _payFunding() private {
        // apply funding if at least one second has passed since last update
        uint256 timeElapsed = block.timestamp - timestampUpdateLast;
        if (timeElapsed > 0) {
            // calculate adjustments to oi due to funding
            bool isLongOverweight = oiLong > oiShort;
            uint256 oiOverweight = isLongOverweight ? oiLong : oiShort;
            uint256 oiUnderweight = isLongOverweight ? oiShort : oiLong;

            // calculate new oi values after funding
            (oiOverweight, oiUnderweight) =
                oiAfterFunding(oiOverweight, oiUnderweight, timeElapsed);

            // pay funding (ie. update market ois)
            oiLong = isLongOverweight ? oiOverweight : oiUnderweight;
            oiShort = isLongOverweight ? oiUnderweight : oiOverweight;

            // set last time market was updated
            timestampUpdateLast = block.timestamp;
        }
    }

    /// @notice Adds open interest and open interest shares to aggregate storage
    /// @notice pairs (oiLong, oiLongShares) or (oiShort, oiShortShares)
    /// @return oiShares_ as the new position's shares of aggregate open interest
    function _addToOiAggregates(uint256 oi, uint256 capOi, bool isLong)
        private
        returns (uint256 oiShares_)
    {
        // cache for gas savings
        uint256 oiTotalOnSide = isLong ? oiLong : oiShort;
        uint256 oiTotalSharesOnSide = isLong ? oiLongShares : oiShortShares;

        // calculate oi shares
        uint256 oiShares = Position.calcOiShares(oi, oiTotalOnSide, oiTotalSharesOnSide);

        // add oi and oi shares to temp aggregate values
        oiTotalOnSide += oi;
        oiTotalSharesOnSide += oiShares;

        // check new total oi on side does not exceed capOi after
        // adjusted for circuit breaker
        uint256 capOiCircuited = capOiAdjustedForCircuitBreaker(capOi);
        require(oiTotalOnSide <= capOiCircuited, "OVLV1:oi>cap");

        // update total aggregate oi and oi shares storage vars
        if (isLong) {
            oiLong = oiTotalOnSide;
            oiLongShares = oiTotalSharesOnSide;
        } else {
            oiShort = oiTotalOnSide;
            oiShortShares = oiTotalSharesOnSide;
        }

        // return new position's oi shares
        oiShares_ = oiShares;
    }

    /// @notice Sets the governance per-market risk parameter
    /// @dev updates funding state of market but does not fetch from oracle
    /// @dev to avoid edge cases when dataIsValid is false
    function setRiskParam(Risk.Parameters name, uint256 value) external onlyFactory {
        // pay funding to update state of market since last interaction
        _payFunding();

        // check then set risk param
        _checkRiskParam(name, value);
        _cacheRiskCalc(name, value);
        params.set(name, value);
    }

    /// @notice Checks the governance per-market risk parameter is valid
    function _checkRiskParam(Risk.Parameters name, uint256 value) private view {
        // checks delta won't cause position to be immediately
        // liquidatable given current leverage cap (capLeverage),
        // liquidation fee rate (liquidationFeeRate), and
        // maintenance margin fraction (maintenanceMarginFraction)
        if (name == Risk.Parameters.Delta) {
            uint256 _delta = value;
            uint256 capLeverage = params.get(Risk.Parameters.CapLeverage);
            uint256 maintenanceMarginFraction =
                params.get(Risk.Parameters.MaintenanceMarginFraction);
            uint256 liquidationFeeRate = params.get(Risk.Parameters.LiquidationFeeRate);
            require(
                capLeverage
                    <= ONE.divDown(
                        2 * _delta + maintenanceMarginFraction.divDown(ONE - liquidationFeeRate)
                    ),
                "OVLV1: max lev immediately liquidatable"
            );
        }

        // checks capLeverage won't cause position to be immediately
        // liquidatable given current spread (delta),
        // liquidation fee rate (liquidationFeeRate), and
        // maintenance margin fraction (maintenanceMarginFraction)
        if (name == Risk.Parameters.CapLeverage) {
            uint256 _capLeverage = value;
            uint256 delta = params.get(Risk.Parameters.Delta);
            uint256 maintenanceMarginFraction =
                params.get(Risk.Parameters.MaintenanceMarginFraction);
            uint256 liquidationFeeRate = params.get(Risk.Parameters.LiquidationFeeRate);
            require(
                _capLeverage
                    <= ONE.divDown(
                        2 * delta + maintenanceMarginFraction.divDown(ONE - liquidationFeeRate)
                    ),
                "OVLV1: max lev immediately liquidatable"
            );
        }

        // checks maintenanceMarginFraction won't cause position
        // to be immediately liquidatable given current spread (delta),
        // liquidation fee rate (liquidationFeeRate),
        // and leverage cap (capLeverage)
        if (name == Risk.Parameters.MaintenanceMarginFraction) {
            uint256 _maintenanceMarginFraction = value;
            uint256 delta = params.get(Risk.Parameters.Delta);
            uint256 capLeverage = params.get(Risk.Parameters.CapLeverage);
            uint256 liquidationFeeRate = params.get(Risk.Parameters.LiquidationFeeRate);
            require(
                capLeverage
                    <= ONE.divDown(
                        2 * delta + _maintenanceMarginFraction.divDown(ONE - liquidationFeeRate)
                    ),
                "OVLV1: max lev immediately liquidatable"
            );
        }

        // checks liquidationFeeRate won't cause position
        // to be immediately liquidatable given current spread (delta),
        // leverage cap (capLeverage), and
        // maintenance margin fraction (maintenanceMarginFraction)
        if (name == Risk.Parameters.LiquidationFeeRate) {
            uint256 _liquidationFeeRate = value;
            uint256 delta = params.get(Risk.Parameters.Delta);
            uint256 capLeverage = params.get(Risk.Parameters.CapLeverage);
            uint256 maintenanceMarginFraction =
                params.get(Risk.Parameters.MaintenanceMarginFraction);
            require(
                capLeverage
                    <= ONE.divDown(
                        2 * delta + maintenanceMarginFraction.divDown(ONE - _liquidationFeeRate)
                    ),
                "OVLV1: max lev immediately liquidatable"
            );
        }

        // checks priceDriftUpperLimit won't cause pow() call in dataIsValid
        // to exceed max
        if (name == Risk.Parameters.PriceDriftUpperLimit) {
            Oracle.Data memory data = IOverlayV1Feed(feed).latest();
            uint256 _priceDriftUpperLimit = value;
            require(
                _priceDriftUpperLimit * data.macroWindow < MAX_NATURAL_EXPONENT,
                "OVLV1: price drift exceeds max exp"
            );
        }
    }

    /// @notice Caches risk param calculations used in market contract
    /// @notice for gas savings
    function _cacheRiskCalc(Risk.Parameters name, uint256 value) private {
        // caches calculations for dpUpperLimit
        // = e**(priceDriftUpperLimit * data.macroWindow)
        if (name == Risk.Parameters.PriceDriftUpperLimit) {
            Oracle.Data memory data = IOverlayV1Feed(feed).latest();
            uint256 _priceDriftUpperLimit = value;
            uint256 pow = _priceDriftUpperLimit * data.macroWindow;
            dpUpperLimit = pow.expUp(); // e**(pow)
            emit CacheRiskCalc(dpUpperLimit);
        }
    }

    /// @notice Pause functions: Build, Unwind, Update and Liquidate
    function pause() external onlyFactory {
        _pause();
    }

    /// @notice Unpause functions: Build, Unwind, Update and Liquidate
    function unpause() external onlyFactory {
        _unpause();
    }

    /// @notice Irreversibly shuts down the market. Can be triggered by
    /// @notice governance through factory contract in the event of an emergency
    function shutdown() external onlyFactory {
        isShutdown = true;
    }

    /// @notice Allows emergency withdrawal of remaining collateral
    /// @notice associated with position. Ignores any outstanding PnL and
    /// @notice funding considerations
    function emergencyWithdraw(uint256 positionId) external hasShutdown {
        // check position exists
        Position.Info memory pos = positions.get(msg.sender, positionId);
        require(pos.exists(), "OVLV1:!position");

        // calculate remaining collateral backing position
        uint256 cost = pos.cost(ONE);
        cost = Math.min(ovl.balanceOf(address(this)), cost); // if cost > balance

        // set fraction remaining to zero so position no longer exists
        pos.fractionRemaining = 0;
        positions.set(msg.sender, positionId, pos);

        // emit withdraw event
        emit EmergencyWithdraw(msg.sender, positionId, cost);

        // transfer available collateral out to position owner
        ovl.transfer(msg.sender, cost);
    }
}
