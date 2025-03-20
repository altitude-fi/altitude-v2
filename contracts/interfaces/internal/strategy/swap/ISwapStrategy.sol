// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../oracles/IPriceSource.sol";

/**
 * @author Altitude Protocol
 **/

interface ISwapStrategy {
    error SWAP_STRATEGY_UNKNOWN_PAIR();
    error SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
    error SWAP_STRATEGY_INVALID_DESTINATION();
    error SWAP_STRATEGY_PRICE_SOURCE_GET_IN_BASE();
    error SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID();
    error SWAP_STRATEGY_ROUTE_NOT_FOUND(address assetFrom, address assetTo);

    event PriceSourceUpdated(address newSource);

    function SLIPPAGE_BASE() external view returns (uint256);

    function swapRouter() external view returns (address);

    function priceSource() external view returns (IPriceSource);

    function setPriceSource(address newPriceSource) external;

    function getMinimumAmountOut(
        address assetFrom,
        address assetTo,
        uint256 baseAmount
    ) external view returns (uint256);

    function getMinimumAmountOut(
        address assetFrom,
        address assetTo,
        uint256 baseAmount,
        uint256 slippage
    ) external view returns (uint256);

    function getMaximumAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut
    ) external view returns (uint256);

    function getMaximumAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut,
        uint256 slippage
    ) external view returns (uint256);

    function swapInBase(
        address assetFrom,
        address assetTo,
        uint256 amount
    ) external returns (uint256);

    function swapOutBase(
        address assetFrom,
        address assetTo,
        uint256 amount,
        uint256 amountInMaximum
    ) external returns (uint256);

    function getAmountOut(
        address assetFrom,
        address assetTo,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function getAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut
    ) external view returns (uint256 amountIn);
}
