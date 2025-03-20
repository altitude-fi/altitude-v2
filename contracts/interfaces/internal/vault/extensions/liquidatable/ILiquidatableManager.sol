// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ILiquidatableManager {
    event LiquidateUser(address user, uint256 supplyTaken, uint256 borrowRepaid);

    event LiquidateUserDefault(address user, uint256 borrowRemaining);

    // Liquidation Errors
    error LQ_V1_MAX_BONUS_OUT_OF_RANGE();
    error LQ_V1_LIQUIDATION_CONSTRAINTS();
    error LQ_V1_INSUFFICIENT_REPAY_AMOUNT();
    error LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE();

    function liquidateUsers(address[] calldata usersForLiquidation, uint256 repayAmountLimit) external;
}
