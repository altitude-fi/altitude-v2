// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../../../strategy/IFlashLoanCallback.sol";

/**
 * @author Altitude Protocol
 **/

interface IGroomableManager is IFlashLoanCallback {
    event RebalanceVaultLimit(bool shouldBorrow, uint256 calculatedAmount);
    event RebalanceVaultBorrow(uint256 amountToBorrow);
    event RebalanceVaultRepay(uint256 amountToRepay, uint256 amountWithdrawn);
    event MigrateLenderStrategy(address oldStrategy, address newStrategy);
    event MigrateFarmDispatcher(address oldFarmDispatcher, address newFarmDispatcher);

    // Groomable Manager Errors
    error GR_V1_MIGRATION_FEE_TOO_HIGH();
    error GR_V1_NOT_FLASH_LOAN_STRATEGY();
    error GR_V1_MIGRATION_OLD_SUPPLY_ERROR();
    error GR_V1_MIGRATION_OLD_BORROW_ERROR();
    error GR_V1_MIGRATION_NEW_SUPPLY_ERROR();
    error GR_V1_MIGRATION_NEW_BORROW_ERROR();
    error GR_V1_FARM_DISPATCHER_ALREADY_ACTIVE();
    error GR_V1_FARM_DISPATCHER_NOT_EMPTY();
    error GR_V1_LENDER_STRATEGY_ALREADY_ACTIVE();

    function migrateLender(address newStrategy) external;

    function migrateFarmDispatcher(address newFarmDispatcher) external;

    function rebalance() external;
}
