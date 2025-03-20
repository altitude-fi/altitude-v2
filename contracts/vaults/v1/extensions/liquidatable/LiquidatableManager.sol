// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../base/JoiningBlockVault.sol";
import "../../../../libraries/utils/HealthFactorCalculator.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";

import "../../../../interfaces/internal/vault/extensions/liquidatable/ILiquidatableManager.sol";

/**
 * @title LiquidatableManager
 * @dev Contract responsible for user liquidations
 * @dev Note! LiquidatableVault storage should be inline with LiquidatableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

contract LiquidatableManager is JoiningBlockVault, ILiquidatableManager {
    /// @notice Liquidate a list of users
    /// @param usersForLiquidation User addresses
    /// @param repayAmountLimit Max amount the liquidator wants to pay
    /// @dev We should call this function after the users' positions have been updated
    function liquidateUsers(address[] calldata usersForLiquidation, uint256 repayAmountLimit) external override {
        TransferHelper.safeTransferFrom(borrowUnderlying, msg.sender, address(this), repayAmountLimit);

        uint8 borrowDecimals = debtToken.decimals();
        uint256 borrowToSupplyExchangeRate = ILenderStrategy(activeLenderStrategy).getInBase(
            borrowUnderlying,
            supplyUnderlying
        );

        // Check and liquidate each user requested
        uint256 liquidatedUsers;
        uint256 totalRepayAmount;
        for (uint256 i; i < usersForLiquidation.length; ) {
            uint256 borrowAmount = debtToken.balanceOf(usersForLiquidation[i]);
            uint256 supplyAmount = supplyToken.balanceOf(usersForLiquidation[i]);

            if (
                !HealthFactorCalculator.isPositionHealthy(
                    activeLenderStrategy,
                    supplyUnderlying,
                    borrowUnderlying,
                    liquidationThreshold,
                    supplyAmount,
                    borrowAmount
                )
            ) {
                uint256 amount = (borrowAmount * liquidatableStorage.maxPositionLiquidation) / 1e18; // 1e18 represents a 100%. maxPositionLiquidation is in percentage
                uint256 supplyLiquidatableAmount;

                {
                    // Calculate the total amount of supply available to cover the liquidation
                    uint256 maxLiquidatableBorrow = (supplyAmount * 10**borrowDecimals) /
                        (borrowToSupplyExchangeRate +
                            ((borrowToSupplyExchangeRate * liquidatableStorage.liquidationBonus) / 1e18)); // 1e18 represents a 100%.

                    // If available supply can't cover full liquidation amount, liquidate as much as possible
                    // Else liquidate as much as possible for this user
                    if (amount > maxLiquidatableBorrow) {
                        amount = maxLiquidatableBorrow;
                        supplyLiquidatableAmount = supplyAmount;
                        emit LiquidateUserDefault(usersForLiquidation[i], borrowAmount - maxLiquidatableBorrow);
                    } else {
                        supplyLiquidatableAmount =
                            (borrowToSupplyExchangeRate *
                                (amount + ((amount * liquidatableStorage.liquidationBonus) / 1e18))) /
                            10**borrowDecimals; // 1e18 represents a 100%.
                    }
                }

                debtToken.burn(usersForLiquidation[i], amount);
                supplyToken.vaultTransfer(usersForLiquidation[i], msg.sender, supplyLiquidatableAmount);

                _updateEarningsRatio(usersForLiquidation[i]);

                totalRepayAmount += amount;

                unchecked {
                    ++liquidatedUsers;
                }

                emit LiquidateUser(usersForLiquidation[i], supplyLiquidatableAmount, amount);
            }

            unchecked {
                ++i;
            }
        }

        if (totalRepayAmount > repayAmountLimit) {
            revert LQ_V1_INSUFFICIENT_REPAY_AMOUNT();
        }

        if (
            liquidatedUsers < liquidatableStorage.minUsersToLiquidate &&
            totalRepayAmount < liquidatableStorage.minRepayAmount
        ) {
            revert LQ_V1_LIQUIDATION_CONSTRAINTS();
        }

        userLastDepositBlock[msg.sender] = block.number;
        _updateEarningsRatio(msg.sender);

        // Adjust repayment to not be bigger than the total balance
        // That could happen due to rounding
        uint256 borrowBalance = ILenderStrategy(activeLenderStrategy).borrowBalance();
        if (totalRepayAmount > borrowBalance) {
            totalRepayAmount = borrowBalance;
        }

        TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, totalRepayAmount);

        ILenderStrategy(activeLenderStrategy).repay(totalRepayAmount);

        // Return the sender any possible overpayment
        TransferHelper.safeTransfer(borrowUnderlying, msg.sender, repayAmountLimit - totalRepayAmount);
    }
}
