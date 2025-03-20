// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/internal/strategy/swap/ISwapStrategyConfiguration.sol";

/**
 * @title SwapStrategyConfiguration Contract
 * @dev Base contract for swap strategy setup
 * @author Altitude Labs
 **/

contract SwapStrategyConfiguration is Ownable, ISwapStrategyConfiguration {
    /** @notice integration with swap provider */
    ISwapStrategy public override swapStrategy;

    constructor(address swapStrategy_) {
        swapStrategy = ISwapStrategy(swapStrategy_);
    }

    /// @notice Every lending/farming strategy has to deal with reward tokens
    /// @notice Because of this, it should use an exchange strategy to swap
    /// @notice the reward tokens for the base asset
    /// @param newSwapStrategy The exchange strategy
    function setSwapStrategy(address newSwapStrategy) external onlyOwner {
        swapStrategy = ISwapStrategy(newSwapStrategy);
        emit UpdateSwapStrategy(newSwapStrategy);
    }
}
