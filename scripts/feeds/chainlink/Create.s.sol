// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import {OverlayV1ChainlinkFeedFactory} from
    "contracts/feeds/chainlink/OverlayV1ChainlinkFeedFactory.sol";
import {ArbSepoliaConfig} from "scripts/config/ArbSepolia.config.sol";
import {ArbMainnetConfig} from "scripts/config/ArbMainnet.config.sol";
import {InternalMovementM1Config} from "scripts/config/InternalMovementM1.config.sol";
import {BartioConfig} from "scripts/config/Bartio.config.sol";
import {ImolaMovementConfig} from "scripts/config/ImolaMovement.config.sol";

// 1. Set required environment variables: ETHERSCAN_API_KEY, DEPLOYER_PK, RPC.
// 2. Update the config file for the network you are deploying to.
// 3. Run with:
// $ source .env
// $ source .env && forge script scripts/feeds/chainlink/Create.s.sol:CreateFeed --rpc-url $RPC -vvvv --broadcast --verify

contract CreateFeed is Script {
    // TODO: update values as needed
    address constant AGGREGATOR = 0x00E99aD888182bFE3E3B2FD5000b08903D57dDE7;
    uint256 constant HEARTBEAT = 2 days;

    function run() external {
        uint256 DEPLOYER_PK = vm.envUint("DEPLOYER_PK");

        vm.startBroadcast(DEPLOYER_PK);

        OverlayV1ChainlinkFeedFactory feedFactory =
            OverlayV1ChainlinkFeedFactory(BartioConfig.FEED_FACTORY);

        // <!---- START DEPLOYMENT ---->

        (bool success,) = AGGREGATOR.call(abi.encodeWithSignature("latestRound()"));
        require(success, "failed to fetch latest round from aggregator");
        require(feedFactory.getFeed(AGGREGATOR) == address(0), "feed already deployed for aggregator");

        address feed = feedFactory.deployFeed(AGGREGATOR, HEARTBEAT);

        // <!-- END DEPLOYMENT -->

        vm.stopBroadcast();

        console2.log("aggregator:", AGGREGATOR);
        console2.log("Feed deployed at:", feed);
    }
}
