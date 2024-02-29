// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@ironblocks/firewall-consumer/contracts/FirewallConsumer.sol";
import "./interfaces/IOverlayV1Deployer.sol";
import "./OverlayV1Market.sol";

contract OverlayV1Deployer is FirewallConsumer, IOverlayV1Deployer {
    address public immutable factory; // factory that has gov permissions
    address public immutable ov; // ov token

    address public feed; // cached feed deploying market on

    // factory modifier for governance sensitive functions
    modifier onlyFactory() {
        require(msg.sender == factory, "OVV1: !factory");
        _;
    }

    constructor(address _ov) {
        factory = msg.sender;
        ov = _ov;
    }

    function parameters() external view returns (address ov_, address feed_, address factory_) {
        ov_ = ov;
        feed_ = feed;
        factory_ = factory;
    }

    function deploy(address _feed) external onlyFactory firewallProtected returns (address market_) {
        // Use the CREATE2 opcode to deploy a new Market contract.
        // Will revert if market which accepts feed in its constructor has already
        // been deployed since salt would be the same and can't deploy with it twice.
        feed = _feed;
        market_ = address(new OverlayV1Market{salt: keccak256(abi.encode(_feed))}());
        delete feed;
    }
}
