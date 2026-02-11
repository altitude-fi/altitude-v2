// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../FarmDropStrategy.sol";
import "../../../SkimStrategy.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../../interfaces/internal/strategy/farming/IBaseERC4626.sol";

/**
 * @title BaseERC4626 Contract
 * @dev Contract for interacting with ERC4626 vaults
 * @author Altitude Labs
 **/

abstract contract BaseERC4626 is FarmDropStrategy, SkimStrategy, IBaseERC4626 {
    IERC4626 public immutable vault;

    constructor(
        address farmDispatcherAddress_,
        address rewardsAddress_,
        address swapStrategy_,
        IERC4626 vault_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_
    )
        FarmDropStrategy(vault_.asset(), farmDispatcherAddress_, rewardsAddress_, rewardAssets_, swapStrategy_)
        SkimStrategy(nonSkimAssets_)
    {
        vault = vault_;
    }

    /// @notice Deposit into the vault
    /// @param amount Amount of asset to deposit
    function _deposit(uint256 amount) internal override {
        amount = _swap(asset, farmAsset, amount);
        TransferHelper.safeApprove(farmAsset, address(vault), amount);
        vault.deposit(amount, address(this));
    }

    /// @notice Withdraw from the vault
    /// @param amountRequested Amount of asset to withdraw
    function _withdraw(uint256 amountRequested) internal virtual override {
        uint256 amountToWithdraw = amountRequested;

        if (farmAsset != asset) {
            // If a conversion is happening, we substitute the requested sum with the
            // input amount we'd need to provide to get it in a swap
            amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountToWithdraw);
        }

        uint256 farmBalance = vault.maxWithdraw(address(this));
        if (farmBalance > 0) {
            // Best effort withdraw
            if (amountToWithdraw > farmBalance) {
                vault.withdraw(farmBalance, address(this), address(this));
            } else {
                vault.withdraw(amountToWithdraw, address(this), address(this));
            }
        }

        // Swap the farm asset to borrow asset (if required)
        _swap(farmAsset, asset, type(uint256).max);
    }

    /// @notice Withdraw as much as possible
    function _emergencyWithdraw() internal virtual override {
        vault.redeem(vault.maxRedeem(address(this)), address(this), address(this));
    }

    /// @notice Return farm asset ammount specific for the farm provider
    function _getFarmAssetAmount() internal view virtual override returns (uint256 farmAssetAmount) {
        uint256 shares = vault.balanceOf(address(this));
        if (shares > 0) {
            farmAssetAmount = vault.convertToAssets(shares);
        }
    }

    /// @notice Internal reusable function
    function _recogniseRewardsInBase() internal override {
        for (uint256 i; i < rewardAssets.length; ++i) {
            _swap(rewardAssets[i], asset, type(uint256).max);
        }

        // Update drop percentage
        FarmDropStrategy._recogniseRewardsInBase();
    }
}
