// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../swap/SwapStrategyConfiguration.sol";
import "../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../interfaces/internal/access/IIngress.sol";
import "../../../interfaces/internal/vault/IVaultCore.sol";
import "../../../interfaces/internal/strategy/farming/IFarmStrategy.sol";
import "../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";

/**
 * @title FarmStrategy Contract
 * @author Altitude Labs
 **/

abstract contract FarmStrategy is Ownable, SwapStrategyConfiguration, IFarmStrategy {
    address public override asset; // baseAsset of farmDispatcher
    address public override farmAsset; // asset of the farm
    address public override farmDispatcher; // farmDispatcher address
    address public override rewardsRecipient; // where to send rewards

    modifier onlyDispatcher() {
        if (msg.sender != farmDispatcher) {
            revert FS_ONLY_DISPATCHER();
        }
        _;
    }

    /// @param farmAssetAddress The address of the token we are farming with
    /// @param farmDispatcherAddress The manager of the strategy
    /// @param rewardsAddress Where to send any reward tokens
    /// @param swapStrategyAddress Swap strategy needed in case farmAsset != baseAsset
    constructor(
        address farmAssetAddress,
        address farmDispatcherAddress,
        address rewardsAddress,
        address swapStrategyAddress
    ) SwapStrategyConfiguration(swapStrategyAddress) {
        farmAsset = farmAssetAddress;
        farmDispatcher = farmDispatcherAddress;
        rewardsRecipient = rewardsAddress;
        asset = IFarmDispatcher(farmDispatcher).asset();
    }

    /// @notice Deposits own funds into the Farm Provider
    /// @param amount amount to deposit
    function deposit(uint256 amount) public virtual override onlyDispatcher {
        if (amount > 0) {
            // Transfer funds from dispatcher
            TransferHelper.safeTransferFrom(asset, msg.sender, address(this), amount);

            _deposit(IERC20(asset).balanceOf(address(this)));

            emit Deposit(amount);
        }
    }

    /// @notice Withdraws from the Farm Provider
    /// @param amountRequested The amount to withdraw
    /// @return amountWithdrawn The amount actually withdrawn
    function withdraw(
        uint256 amountRequested
    ) public virtual override onlyDispatcher returns (uint256 amountWithdrawn) {
        if (amountRequested > 0) {
            // When trying to withdraw all
            if (amountRequested == type(uint256).max) {
                // balanceAvailable() skips the swap slippage check, as that will happen in the actual withdraw
                amountRequested = balanceAvailable();
            }

            _withdraw(amountRequested);
            amountWithdrawn = IERC20(asset).balanceOf(address(this));

            if (amountWithdrawn > 0) {
                TransferHelper.safeTransfer(asset, msg.sender, amountWithdrawn);
            }

            emit Withdraw(amountWithdrawn);
        }
    }

    /// @notice Withdraw everything from the farm with minimal constraints
    /// @dev Should be invoked via protected rpc
    /// @dev We may want to perform intermediate actions, so this is step one of a two step process
    /// @dev Step two is emergencySwap()
    function emergencyWithdraw() public virtual onlyOwner {
        _emergencyWithdraw();

        emit EmergencyWithdraw();
    }

    /// @notice Swap specified tokens to asset
    /// @param assets The assets to swap
    /// @return amountWithdrawn The amount withdrawn after swap
    function emergencySwap(
        address[] calldata assets
    ) public virtual override onlyOwner returns (uint256 amountWithdrawn) {
        _emergencySwap(assets);

        amountWithdrawn = IERC20(asset).balanceOf(address(this));
        TransferHelper.safeTransfer(asset, farmDispatcher, amountWithdrawn);

        emit EmergencySwap();
    }

    /// @notice Claim and swap reward tokens to base asset. Then transfer to the dispatcher for compounding
    /// @return rewards An amount of rewards being recognised
    function recogniseRewardsInBase() public virtual override returns (uint256 rewards) {
        _recogniseRewardsInBase();

        rewards = IERC20(asset).balanceOf(address(this));
        TransferHelper.safeTransfer(asset, rewardsRecipient, rewards);

        emit RewardsRecognition(rewards);
    }

    /// @notice Return the balance in borrow asset excluding rewards (includes slippage validations)
    /// @dev Reverts if slippage is too high
    /// @return balance that can be withdrawn from the farm
    function balance() public view virtual returns (uint256) {
        // Get amount of tokens
        uint256 farmAssetAmount = _getFarmAssetAmount();
        (uint256 totalBalance, uint256 swapAmount) = _balance(farmAssetAmount);

        if (swapAmount > 0) {
            // Validate slippage
            uint256 minimumAssetAmount = swapStrategy.getMinimumAmountOut(farmAsset, asset, farmAssetAmount);

            if (swapAmount < minimumAssetAmount) {
                // Amount is no good since slippage is too high.
                // @dev harvest() earnings calculation relies on .balance() so it is important to revert on a bad value
                revert SSC_SWAP_AMOUNT(minimumAssetAmount, swapAmount);
            }
        }

        return totalBalance;
    }

    /// @notice Return the balance in borrow asset excluding rewards (no slippage validations)
    /// @dev Function will not revert on high slippage, should used with care in transactions
    /// @return availableBalance Balance that can be withdrawn from the farm
    function balanceAvailable() public view virtual returns (uint256 availableBalance) {
        // No slippage validations
        (availableBalance, ) = _balance(_getFarmAssetAmount());
    }

    /// @notice Return the max amount that can be withdrawn at the moment
    /// @param farmAssetAmount The amount from the farm provider
    /// @return totalBalance The amount available to be withdrawn (including amount swapped)
    /// @return swapAmount Amount of totalBalance that is subject to swapping
    function _balance(
        uint256 farmAssetAmount
    ) internal view virtual returns (uint256 totalBalance, uint256 swapAmount) {
        totalBalance = IERC20(asset).balanceOf(address(this));
        if (farmAssetAmount > 0) {
            if (farmAsset == asset) {
                totalBalance += farmAssetAmount;
            } else {
                // amount of borrow asset we'd get if we swap
                swapAmount = swapStrategy.getAmountOut(farmAsset, asset, farmAssetAmount);

                totalBalance += swapAmount;
            }
        }
    }

    function _getFarmAssetAmount() internal view virtual returns (uint256);

    function _deposit(uint256 amount) internal virtual;

    function _withdraw(uint256 amount) internal virtual;

    function _emergencyWithdraw() internal virtual;

    function _emergencySwap(address[] calldata assets) internal virtual;

    function _recogniseRewardsInBase() internal virtual;
}
