// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {Test, console2} from "forge-std/Test.sol";
import {OverlayV1Market} from "contracts/OverlayV1Market.sol";
import {OverlayV1Factory} from "contracts/OverlayV1Factory.sol";
import {OverlayV1Token} from "contracts/OverlayV1Token.sol";
import {OverlayV1Deployer} from "contracts/OverlayV1Deployer.sol";
import {Position} from "contracts/libraries/Position.sol";

contract MarketTest is Test {
    bytes32 constant ADMIN = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER");
    bytes32 constant BURNER_ROLE = keccak256("BURNER");
    bytes32 constant GOVERNOR_ROLE = keccak256("GOVERNOR");
    bytes32 constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER");

    address immutable GOVERNOR = makeAddr("governor");
    address immutable FEE_RECIPIENT = makeAddr("fee-recipient");
    address immutable PAUSER = makeAddr("pauser");
    address immutable USER = makeAddr("user");
    address constant FEED_FACTORY = 0x92ee7A26Dbc18E9C0157831d79C2906A02fD1FAe;
    address constant FEED = 0x46B4143CAf2fE2965349FCa53730e83f91247E2C;
    address constant SEQUENCER_ORACLE = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    OverlayV1Token ovl;
    OverlayV1Factory factory;
    OverlayV1Market market;
    OverlayV1Deployer deployer;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC"), 169_490_320);
        ovl = new OverlayV1Token();
        factory = new OverlayV1Factory(address(ovl), FEE_RECIPIENT, SEQUENCER_ORACLE, 0);

        ovl.grantRole(ADMIN, address(factory));
        ovl.grantRole(ADMIN, GOVERNOR);
        ovl.grantRole(MINTER_ROLE, GOVERNOR);
        ovl.grantRole(GOVERNOR_ROLE, GOVERNOR);
        ovl.grantRole(PAUSER_ROLE, PAUSER);

        uint256[15] memory params;
        params[0] = 115740740740;
        params[1] = 750000000000000000;
        params[2] = 2475000000000000;
        params[3] = 5000000000000000000;
        params[4] = 20000000000000000000000;
        params[5] = 10000000000000000000;
        params[6] = 2592000;
        params[7] = 1666666666666666666666;
        params[8] = 40000000000000000;
        params[9] = 50000000000000000;
        params[10] = 50000000000000000;
        params[11] = 750000000000000;
        params[12] = 100000000000000;
        params[13] = 87000000000000;
        params[14] = 250;

        vm.startPrank(GOVERNOR);
        factory.addFeedFactory(FEED_FACTORY);

        market = OverlayV1Market(factory.deployMarket(FEED_FACTORY, FEED, params));

        ovl.mint(USER, 100e18);
    }

    // Test pausable markets

    function testPause() public {
        vm.startPrank(USER);
        ovl.approve(address(market), type(uint256).max);
        // Build postion 0
        market.build(1e18, 1e18, true, type(uint256).max);
        // Build postion 1
        market.build(1e18, 1e18, true, type(uint256).max);
        // Unwind postion 0
        market.unwind(0, 1e18, 0);

        vm.startPrank(PAUSER);
        factory.pause(FEED);

        vm.startPrank(USER);
        vm.expectRevert("Pausable: paused");
        market.build(1e18, 1e18, true, type(uint256).max);
        vm.expectRevert("Pausable: paused");
        market.unwind(1, 1e18, 0);
        vm.expectRevert("Pausable: paused");
        market.liquidate(USER, 1);

        vm.startPrank(PAUSER);

        factory.unpause(FEED);

        vm.startPrank(USER);
        market.build(1e18, 1e18, true, type(uint256).max);
        market.unwind(1, 1e18, 0);
    }

    function testRoles() public {
        vm.startPrank(USER);
        vm.expectRevert();
        factory.pause(FEED);

        vm.startPrank(GOVERNOR);
        vm.expectRevert();
        factory.pause(FEED);

        vm.startPrank(PAUSER);
        factory.pause(FEED);

        vm.startPrank(USER);
        vm.expectRevert();
        factory.unpause(FEED);

        vm.startPrank(GOVERNOR);
        vm.expectRevert();
        factory.unpause(FEED);

        vm.startPrank(PAUSER);
        factory.unpause(FEED);
    }

    // Test shutdown markets

    function testShutdown(uint256 _fraction) public {
        _fraction = bound(_fraction, 1e14, 9999e14);

        vm.startPrank(USER);

        ovl.approve(address(market), type(uint256).max);
        // Build postion 0
        market.build(1e18, 1e18, true, type(uint256).max);
        // Build postion 1
        market.build(1e18, 1e18, true, type(uint256).max);
        // Build postion 2
        market.build(1e18, 1e18, true, type(uint256).max);
        // Unwind postion 0
        market.unwind(0, 1e18, 0);
        // Unwind _fraction of postion 1
        market.unwind(1, _fraction, 0);

        vm.expectRevert("OVLV1: !shutdown");
        market.emergencyWithdraw(1);

        vm.startPrank(GOVERNOR);
        vm.expectRevert("OVLV1: !guardian");
        factory.shutdown(FEED);

        ovl.grantRole(GUARDIAN_ROLE, GOVERNOR);
        factory.shutdown(FEED);

        vm.startPrank(USER);
        vm.expectRevert("OVLV1: shutdown");
        market.build(1e18, 1e18, true, type(uint256).max);
        vm.expectRevert("OVLV1: shutdown");
        market.unwind(1, 1e18, 0);
        vm.expectRevert("OVLV1: shutdown");
        market.liquidate(USER, 1);

        uint256 balanceBefore = ovl.balanceOf(USER);
        (uint96 notionalInitial,,,,,,, uint16 fractionRemaining) =
            market.positions(keccak256(abi.encodePacked(USER, uint256(1))));
        market.emergencyWithdraw(1);
        assertEq(balanceBefore + notionalInitial * fractionRemaining / 1e4, ovl.balanceOf(USER));
        balanceBefore = ovl.balanceOf(USER);
        (notionalInitial,,,,,,, fractionRemaining) =
            market.positions(keccak256(abi.encodePacked(USER, uint256(2))));
        market.emergencyWithdraw(2);
        assertEq(balanceBefore + notionalInitial * fractionRemaining / 1e4, ovl.balanceOf(USER));

        assertEq(ovl.balanceOf(address(market)), 0);
    }

    event Update(uint256 oiLong, uint256 oiShort);

    function testUpdateEventEmitting() public {
        vm.startPrank(USER);

        ovl.approve(address(market), type(uint256).max);
        market.build(1e18, 1e18, true, type(uint256).max);

        uint256 oiLong = market.oiLong();
        uint256 oiShort = market.oiShort();
        uint256 timeElapsed = block.timestamp - market.timestampUpdateLast();
        bool isLongOverweight = oiLong > oiShort;
        uint256 oiOverweight = isLongOverweight ? oiLong : oiShort;
        uint256 oiUnderweight = isLongOverweight ? oiShort : oiLong;

        (oiOverweight, oiUnderweight) =
            market.oiAfterFunding(oiOverweight, oiUnderweight, timeElapsed);
        uint256 newoiLong = isLongOverweight ? oiOverweight : oiUnderweight;
        uint256 newoiShort = isLongOverweight ? oiUnderweight : oiOverweight;

        vm.expectEmit(false, false, false, true);
        emit Update(newoiLong, newoiShort);
        market.update();

        vm.stopPrank();

        assertEq(market.oiLong(), newoiLong);
        assertEq(market.oiShort(), newoiShort);
    }
}
