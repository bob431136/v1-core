pragma solidity 0.8.10;

import "forge-std/StdJson.sol";
import {Test, console2} from "forge-std/Test.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../../../contracts/feeds/chainlink/OverlayV1ChainlinkFeed.sol";
import "../../../contracts/libraries/Oracle.sol";

contract ChainlinkFeedTest is Test {
    using Oracle for Oracle.Data;
    using stdJson for string;

    function append(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    struct JsonConfig {
        int256 answerDesiredValue;
        int256 answerPercentageDriftTolerance;
        uint64 blockNumber;
        address feedAddress;
        uint256 heartbeat;
        uint256 macroWindowPercentageDriftTolerance;
        uint256 microWindowPercentageDriftTolerance;
        uint8 roundCount;
    }

    string chainlinkRPC;
    JsonConfig config;
    AggregatorV3Interface feed;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = append(root, "/config/chainlinkFeed.json");
        string memory json = vm.readFile(path);
        bytes memory jsonBytes = json.parseRaw("");

        config = abi.decode(jsonBytes, (JsonConfig));
        feed = AggregatorV3Interface(config.feedAddress);

        chainlinkRPC = vm.envString("SEPOLIA_RPC");
        vm.createSelectFork(chainlinkRPC, config.blockNumber);
    }

    function test_ConsecutiveRoundId() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        uint256 updatedAt;
        uint256 previousUpdatedAt = type(uint256).max;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (,,, updatedAt,) = feed.getRoundData(index);

            assertLe(updatedAt, previousUpdatedAt);
            previousUpdatedAt = updatedAt;
        }
    }

    function test_AnswerValue() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        int256 answerCeiling;
        int256 answerFloor;
        int256 answerDriftAbsolute;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (, int256 answer,,,) = feed.getRoundData(index);

            answerDriftAbsolute =
                config.answerDesiredValue * config.answerPercentageDriftTolerance / 100;
            answerCeiling = config.answerDesiredValue + answerDriftAbsolute;
            answerFloor = config.answerDesiredValue - answerDriftAbsolute;

            assertLt(answer, answerCeiling);
            assertGt(answer, answerFloor);
        }
    }

    // we check last n rounds and see if timestamps are not bigger than the current block.timestamp
    function test_TimestampsInSeconds() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        uint256 updatedAt;
        uint256 startedAt;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (,, startedAt, updatedAt,) = feed.getRoundData(index);

            int256 updatedAtDiff = int256(block.timestamp) - int256(updatedAt);
            int256 startedAtDiff = int256(block.timestamp) - int256(startedAt);

            assertGt(updatedAtDiff, 0);
            assertGt(startedAtDiff, 0);
        }
    }

    function test_Heartbeat() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        uint256 updatedAt;
        uint256 previousUpdatedAt = block.timestamp;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (,,, updatedAt,) = feed.getRoundData(index);

            assertLt(previousUpdatedAt - updatedAt, config.heartbeat);
            previousUpdatedAt = updatedAt;
        }
    }

    function test_AnsweredInRoundCompatability() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        uint256 answeredInRound;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (,,,, answeredInRound) = feed.getRoundData(index);

            uint80 expectedAnsweredInRound = uint80(answeredInRound);
            assertEq(answeredInRound, expectedAnsweredInRound);
        }
    }

    function test_TWAP() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();

        OverlayV1ChainlinkFeed wrappedFeed =
            new OverlayV1ChainlinkFeed(address(0), config.feedAddress, 600, 3600, config.heartbeat);

        Oracle.Data memory data = wrappedFeed.latest();

        uint256 normalizedAnswerDesiredValue =
            uint256(config.answerDesiredValue) * 10 ** (18 - feed.decimals());

        uint256 macroWindowDriftAbsolute =
            normalizedAnswerDesiredValue * config.macroWindowPercentageDriftTolerance / 100;
        uint256 microWindowDriftAbsolute =
            normalizedAnswerDesiredValue * config.microWindowPercentageDriftTolerance / 100;

        uint256 macroWindowCeiling = normalizedAnswerDesiredValue + macroWindowDriftAbsolute;
        uint256 macroWindowFloor = normalizedAnswerDesiredValue - macroWindowDriftAbsolute;
        uint256 microWindowCeiling = normalizedAnswerDesiredValue + microWindowDriftAbsolute;
        uint256 microWindowFloor = normalizedAnswerDesiredValue - microWindowDriftAbsolute;

        assertGt(data.priceOverMicroWindow, microWindowFloor);
        assertLt(data.priceOverMicroWindow, microWindowCeiling);
        assertGt(data.priceOverMacroWindow, macroWindowFloor);
        assertLt(data.priceOverMacroWindow, macroWindowCeiling);
    }

    function test_AnswerValueIsNotStale() public {
        (uint80 latestRoundId,,,,) = feed.latestRoundData();
        int256 answer;
        int256 previousAnswer = type(int256).max;

        for (uint80 index = latestRoundId; index > latestRoundId - config.roundCount; index--) {
            (, answer,,,) = feed.getRoundData(index);

            console2.log("Round ID: ", index);
            console2.log("Answer: ", answer);
            console2.log("-----------------");

            assertNotEq(answer, previousAnswer);
            previousAnswer = answer;
        }
    }

    function test_updatedAtAsSameAsBlockTimestamp() public {
        (uint80 latestRoundId,,, uint256 updatedAt,) = feed.latestRoundData();

        console2.log("updatedAt timestamp: ", updatedAt);
        console2.log("updatedAt block: ", findBlockByTimestamp(updatedAt));
        console2.log("block.timestamp: ", block.timestamp);
        console2.log("block.number: ", block.number);
        console2.log("latestRoundId: ", latestRoundId);
        console2.log("-----------------");

        uint256 updatedAtBlock = findBlockByTimestamp(updatedAt);
        vm.createSelectFork(chainlinkRPC, updatedAtBlock - 1);

        (uint80 newRoundId,, uint256 newUpdatedAt,,) = feed.latestRoundData();
        console2.log("new updatedAt timestamp: ", newUpdatedAt);
        console2.log("new RoundId: ", newRoundId);

        assertNotEq(newRoundId, latestRoundId);
    }

    function findBlockByTimestamp(uint256 targetTimestamp) internal returns (uint256) {
        uint256 latestBlockNumber = block.number;
        uint256 step = 5000;
        uint256 low = 0;
        uint256 high = latestBlockNumber - 20_000;

        while (true) {
            uint256 highTimestamp = getBlockTimestamp(high);
            if (highTimestamp >= targetTimestamp || high >= latestBlockNumber) {
                break;
            }
            low = high;
            high = high + step < latestBlockNumber ? high + step : latestBlockNumber;
        }

        while (low < high) {
            uint256 mid = (low + high) / 2;
            uint256 midTimestamp = getBlockTimestamp(mid);

            if (midTimestamp < targetTimestamp) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return low;
    }

    function getBlockTimestamp(uint256 blockNumber) internal returns (uint256) {
        vm.createSelectFork(chainlinkRPC, blockNumber);

        return block.timestamp;
    }
}
