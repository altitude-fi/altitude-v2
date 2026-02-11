// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../FarmDropStrategy.sol";
import "../../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import "../../../../interfaces/internal/strategy/farming/ISwapHoldStrategy.sol";

/**
 * @title StrategySwapHold Contract
 * @dev Strategy holding yield bearing farm token
 * @author Altitude Labs
 **/

contract StrategySwapHold is Ownable, FarmDropStrategy, ISwapHoldStrategy {
    constructor(
        address farmAsset_,
        address farmDispatcherAddress_,
        address rewardsAddress_,
        address swapStrategy_,
        address[] memory rewardAssets_
    ) FarmDropStrategy(farmAsset_, farmDispatcherAddress_, rewardsAddress_, rewardAssets_, swapStrategy_) {
        if (IFarmDispatcher(farmDispatcher).asset() == farmAsset_) {
            revert SWAP_HOLD_SAME_ASSETS();
        }
    }

    /// @notice Swap and hold
    /// @param amount Amount of asset to deposit
    function _deposit(uint256 amount) internal override {
        _swap(asset, farmAsset, amount);
    }

    /// @notice Swap and withdraw
    /// @param amountRequested Amount of asset to withdraw
    function _withdraw(uint256 amountRequested) internal override {
        uint256 amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountRequested);

        uint256 farmBalance = IERC20(farmAsset).balanceOf(address(this));
        if (amountToWithdraw > farmBalance) {
            amountToWithdraw = farmBalance;
        }

        _swap(farmAsset, asset, amountToWithdraw);
    }

    /// @notice Return farm asset balance
    function _getFarmAssetAmount() internal view virtual override returns (uint256) {
        return IERC20(farmAsset).balanceOf(address(this));
    }

    /// @notice Swap any present reward tokens to asset
    function _recogniseRewardsInBase() internal override {
        for (uint256 i; i < rewardAssets.length; ++i) {
            _swap(rewardAssets[i], asset, type(uint256).max);
        }

        // Update drop percentage
        super._recogniseRewardsInBase();
    }

    /// @notice Simulate emergency withdrawal
    /// @dev Nothing to do - the contract already holds farmAsset
    function _emergencyWithdraw() internal override {}
}
