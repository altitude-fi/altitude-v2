// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../FarmDropStrategy.sol";
import "../../../SkimStrategy.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../../interfaces/internal/strategy/farming/IMorphoVault.sol";

/**
 * @title MorphoVault Contract
 * @dev Contract for interacting with MetaMorpho vaults
 * @author Altitude Labs
 **/

contract MorphoVault is FarmDropStrategy, SkimStrategy, IMorphoVault {
    IERC4626 public immutable morphoVault;
    address[] public rewardAssets;

    constructor(
        address farmDispatcherAddress_,
        address rewardsAddress_,
        address swapStrategy_,
        IERC4626 morphoVault_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_
    )
        FarmDropStrategy(morphoVault_.asset(), farmDispatcherAddress_, rewardsAddress_, swapStrategy_)
        SkimStrategy(nonSkimAssets_)
    {
        morphoVault = morphoVault_;
        rewardAssets = rewardAssets_;
    }

    /// @notice Sets the reward tokens to be recognised
    /// @param rewardAssets_ Token addresses
    function setRewardAssets(address[] memory rewardAssets_) external onlyOwner {
        emit SetRewardAssets(rewardAssets, rewardAssets_);

        rewardAssets = rewardAssets_;
    }

    /// @notice Deposit into Morpho
    /// @param amount Amount of asset to deposit
    function _deposit(uint256 amount) internal override {
        amount = _swap(asset, farmAsset, amount);
        TransferHelper.safeApprove(farmAsset, address(morphoVault), amount);
        morphoVault.deposit(amount, address(this));
    }

    /// @notice Withdraw from Morpho
    /// @param amountRequested Amount of asset to withdraw
    function _withdraw(uint256 amountRequested) internal override {
        uint256 amountToWithdraw = amountRequested;

        if (farmAsset != asset) {
            // If a conversion is happening, we substitute the requested sum with the
            // input amount we'd need to provide to get it in a swap
            amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountToWithdraw);
        }

        uint256 farmBalance = morphoVault.maxWithdraw(address(this));

        if (amountToWithdraw > farmBalance) {
            // If requested amount is more than we have, recognise rewards and withdraw all
            if (farmBalance > 0) {
                morphoVault.withdraw(farmBalance, address(this), address(this));
            }
        } else {
            // Else withdraw the requested amount
            if (farmBalance > 0) {
                morphoVault.withdraw(amountToWithdraw, address(this), address(this));
            }
        }

        // Swap the farm asset to borrow asset (if required)
        _swap(farmAsset, asset, type(uint256).max);
    }

    /// @notice Withdraw as much as possible from Morpho
    function _emergencyWithdraw() internal override {
        morphoVault.redeem(morphoVault.maxRedeem(address(this)), address(this), address(this));
    }

    /// @notice Swap assets to borrow asset
    /// @param assets Array of assets to swap
    function _emergencySwap(address[] calldata assets) internal override {
        for (uint256 i; i < assets.length; ++i) {
            _swap(assets[i], asset, type(uint256).max);
        }
    }

    /// @notice Return farm asset ammount specific for the farm provider
    function _getFarmAssetAmount() internal view virtual override returns (uint256 farmAssetAmount) {
        uint256 shares = morphoVault.balanceOf(address(this));
        if (shares > 0) {
            farmAssetAmount = morphoVault.convertToAssets(shares);
        }
    }

    /// @notice Internal reusable function
    function _recogniseRewardsInBase() internal override {
        for (uint256 i; i < rewardAssets.length; ++i) {
            _swap(rewardAssets[i], asset, type(uint256).max);
        }

        // Update drop percentage
        super._recogniseRewardsInBase();
    }

    /// @notice Swap between different assets
    /// @param inputAsset Input asset address
    /// @param outputAsset Output asset address
    /// @param amount Amount to swap
    function _swap(
        address inputAsset,
        address outputAsset,
        uint256 amount
    ) internal returns (uint256) {
        if (inputAsset != outputAsset) {
            if (amount == type(uint256).max) {
                amount = IERC20(inputAsset).balanceOf(address(this));
            }

            if (amount > 0) {
                TransferHelper.safeApprove(inputAsset, address(swapStrategy), amount);
                amount = swapStrategy.swapInBase(inputAsset, outputAsset, amount);
            }
        }

        return amount;
    }
}
