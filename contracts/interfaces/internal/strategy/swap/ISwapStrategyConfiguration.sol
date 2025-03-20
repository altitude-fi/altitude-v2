// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./ISwapStrategy.sol";

interface ISwapStrategyConfiguration {
    error SSC_SWAP_AMOUNT(uint256 actualAmount, uint256 expectedAmount);

    event UpdateSwapStrategy(address newSwapStrategy);

    function swapStrategy() external view returns (ISwapStrategy);

    function setSwapStrategy(address newSwapStrategy) external;
}
