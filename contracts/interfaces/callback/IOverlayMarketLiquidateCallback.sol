// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title Callback for OverlayV1Market#liquidate
interface IOverlayMarketLiquidateCallback {
    /// @notice Called to `owner` after executing a liquidation.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param positionId The positionId of the liquidated position
    function overlayMarketLiquidateCallback(uint256 positionId) external;
}
