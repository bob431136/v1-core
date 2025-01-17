// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

bytes32 constant MINTER_ROLE = keccak256("MINTER");
bytes32 constant BURNER_ROLE = keccak256("BURNER");
bytes32 constant GOVERNOR_ROLE = keccak256("GOVERNOR");
bytes32 constant GUARDIAN_ROLE = keccak256("GUARDIAN");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER");
bytes32 constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER");
bytes32 constant LIQUIDATE_CALLBACK_ROLE = keccak256("LIQUIDATE_CALLBACK");

interface IOverlayV1Token is IAccessControl, IERC20 {
    // mint/burn
    function mint(address _recipient, uint256 _amount) external;

    function burn(uint256 _amount) external;
}
