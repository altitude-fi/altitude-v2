// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../erc4626/Strategy4626Merkl.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";

/**
 * @title MorphoVaultV2 Contract
 * @dev Contract for interacting with Morpho V2 vaults
 * @author Altitude Labs
 **/

contract MorphoVaultV2 is Strategy4626Merkl {
    /// @dev Note that maxWithdraw, maxRedeem always return 0 in Morpho's V2 Vault implementation

    constructor(
        address farmDispatcherAddress_,
        address rewardsAddress_,
        address swapStrategy_,
        IERC4626 morphoVault_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_,
        address merklDistributor_
    )
        Strategy4626Merkl(
            farmDispatcherAddress_,
            rewardsAddress_,
            swapStrategy_,
            morphoVault_,
            rewardAssets_,
            nonSkimAssets_,
            merklDistributor_
        )
    {}

    /// @notice Withdraw from Morpho
    /// @param amountRequested Amount of asset to withdraw
    function _withdraw(uint256 amountRequested) internal override {
        uint256 amountToWithdraw = amountRequested;

        if (farmAsset != asset) {
            // If a conversion is happening, we substitute the requested sum with the
            // input amount we'd need to provide to get it in a swap
            amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountToWithdraw);
        }

        uint256 farmBalance = _getFarmAssetAmount();
        if (farmBalance > 0) {
            if (amountToWithdraw > farmBalance) {
                vault.withdraw(farmBalance, address(this), address(this));
            } else {
                vault.withdraw(amountToWithdraw, address(this), address(this));
            }
        }

        // Swap the farm asset to borrow asset (if required)
        _swap(farmAsset, asset, type(uint256).max);
    }

    /// @notice Withdraw as much as possible from Morpho
    function _emergencyWithdraw() internal override {
        vault.redeem(vault.balanceOf(address(this)), address(this), address(this));
    }
}
