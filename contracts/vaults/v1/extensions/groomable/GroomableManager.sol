// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../base/VaultStorage.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../../libraries/utils/HealthFactorCalculator.sol";
import "../../../../interfaces/internal/flashloan/IFlashLoanStrategy.sol";
import "../../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import "../../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";
import "../../../../interfaces/internal/vault/extensions/groomable/IGroomableManager.sol";

/**
 * @title GroomableManager
 * @dev Proxy implementation for:
 * @dev - vault rebalancing
 * @dev - migrating to a new lender provider
 * @dev - migrating to a new farm provider
 * @dev Note! The groomable manager storage should be inline with GroomableVaultV1
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

contract GroomableManager is VaultStorage, IGroomableManager {
    /// @notice Migrate from one lendingStrategy to another
    /// @param newStrategy The strategy to be migrated to
    function migrateLender(address newStrategy) public override {
        if (newStrategy == activeLenderStrategy) {
            revert GR_V1_LENDER_STRATEGY_ALREADY_ACTIVE();
        }

        uint256 borrowBalanceBefore = ILenderStrategy(activeLenderStrategy).borrowBalance();
        uint256 supplyBalanceBefore = ILenderStrategy(activeLenderStrategy).supplyBalance();
        uint256 borrowPrincipalBefore = ILenderStrategy(activeLenderStrategy).borrowPrincipal();
        uint256 supplyPrincipalBefore = ILenderStrategy(activeLenderStrategy).supplyPrincipal();

        // If there are no borrows migrate supply
        // else take flashloan and execute actions needed to repay flashloan
        if (borrowBalanceBefore == 0) {
            _migrateSupply(newStrategy);
        } else {
            FlashLoan.Info memory info = FlashLoan.Info({
                targetContract: address(this),
                asset: borrowUnderlying,
                amount: borrowBalanceBefore,
                data: abi.encode(newStrategy, borrowBalanceBefore)
            });
            IFlashLoanStrategy(groomableStorage.flashLoanStrategy).flashLoan(info);
        }

        // Some sanity checks that the flashLoan() call actually migrated
        // Old provider is empty
        if (ILenderStrategy(activeLenderStrategy).supplyBalance() > 0) {
            revert GR_V1_MIGRATION_OLD_SUPPLY_ERROR();
        }

        if (ILenderStrategy(activeLenderStrategy).borrowBalance() > 0) {
            revert GR_V1_MIGRATION_OLD_BORROW_ERROR();
        }

        // If old had balances then the new should as well
        if (supplyBalanceBefore > 0 && (ILenderStrategy(newStrategy).supplyBalance() == 0)) {
            revert GR_V1_MIGRATION_NEW_SUPPLY_ERROR();
        }

        if (borrowBalanceBefore > 0 && (ILenderStrategy(newStrategy).borrowBalance() == 0)) {
            revert GR_V1_MIGRATION_NEW_BORROW_ERROR();
        }

        supplyToken.setActiveLenderStrategy(newStrategy);
        debtToken.setActiveLenderStrategy(newStrategy);

        // Deposit and withdraw in the new strategy has updated the principals to the current values.
        // We need the principal values from the old strategy, as the InterestToken indexes correspond to them.
        // Also this will preserve any supply loss state that we may need to snapshot later
        ILenderStrategy(newStrategy).updatePrincipal(supplyPrincipalBefore, borrowPrincipalBefore);

        emit MigrateLenderStrategy(activeLenderStrategy, newStrategy);
        activeLenderStrategy = newStrategy;
    }

    /// @notice Migrate from one FarmDispatcher to another
    /// @param newFarmDispatcher The new contract to be migrated to
    function migrateFarmDispatcher(address newFarmDispatcher) external override {
        address oldFarmDispatcher = activeFarmStrategy;
        if (newFarmDispatcher == oldFarmDispatcher) {
            revert GR_V1_FARM_DISPATCHER_ALREADY_ACTIVE();
        }

        uint256 withdrawn = IFarmDispatcher(oldFarmDispatcher).withdraw(type(uint256).max);
        if (IFarmDispatcher(oldFarmDispatcher).balance() > 0) {
            revert GR_V1_FARM_DISPATCHER_NOT_EMPTY();
        }
        activeFarmStrategy = newFarmDispatcher;
        TransferHelper.safeTransfer(borrowUnderlying, newFarmDispatcher, withdrawn);
        IFarmDispatcher(newFarmDispatcher).dispatch();

        emit MigrateFarmDispatcher(oldFarmDispatcher, newFarmDispatcher);
    }

    /// @notice Flash Loan Strategy will call this function to execute the lending migration
    /// @param params Flash loan data
    /// @param migrationFee The fee that needs to be returned to the lash loan strategy
    function flashLoanCallback(bytes calldata params, uint256 migrationFee) external override {
        (address newStrategy, uint256 loanAmount) = abi.decode(params, (address, uint256));

        if (groomableStorage.flashLoanStrategy != msg.sender) {
            revert GR_V1_NOT_FLASH_LOAN_STRATEGY();
        }

        if (
            migrationFee > (loanAmount * groomableStorage.maxMigrationFeePercentage) / 1e18 // 1e18 represents a 100%. maxMigrationFeePercentage is in percentage
        ) {
            revert GR_V1_MIGRATION_FEE_TOO_HIGH();
        }

        TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, loanAmount);
        ILenderStrategy(activeLenderStrategy).repay(loanAmount);

        _migrateSupply(newStrategy);

        ILenderStrategy(newStrategy).borrow(loanAmount + migrationFee);

        TransferHelper.safeTransfer(borrowUnderlying, msg.sender, loanAmount + migrationFee);
    }

    /// @notice Execute migration of current active lender strategy to a new one
    /// @param newStrategy The new strategy to migrate to
    function _migrateSupply(address newStrategy) internal {
        uint256 balanceBefore = IERC20(supplyUnderlying).balanceOf(address(this));

        // Rewards are not accounted in withdrawAll. They should have been recognised beforehand.
        ILenderStrategy(activeLenderStrategy).withdrawAll();

        uint256 balanceAfter = IERC20(supplyUnderlying).balanceOf(address(this));

        TransferHelper.safeTransfer(supplyUnderlying, newStrategy, balanceAfter - balanceBefore);

        ILenderStrategy(newStrategy).deposit(balanceAfter - balanceBefore);
    }

    /// @notice Process vault rebalancing (re-usable function)
    function rebalance() public override {
        (bool shouldBorrow, uint256 calculatedAmount, uint256 actionableAmount) = calcRebalance();

        if (actionableAmount == 0) {
            emit RebalanceVaultLimit(shouldBorrow, calculatedAmount);
        } else {
            if (shouldBorrow) {
                debtToken.mint(address(this), actionableAmount);
                ILenderStrategy(activeLenderStrategy).borrow(actionableAmount);

                TransferHelper.safeTransfer(borrowUnderlying, activeFarmStrategy, actionableAmount);
                IFarmDispatcher(activeFarmStrategy).dispatch();

                emit RebalanceVaultBorrow(actionableAmount);
            } else {
                uint256 amountWithdrawn = IFarmDispatcher(activeFarmStrategy).withdraw(actionableAmount);

                debtToken.burn(address(this), amountWithdrawn);
                TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, amountWithdrawn);
                ILenderStrategy(activeLenderStrategy).repay(amountWithdrawn);

                emit RebalanceVaultRepay(actionableAmount, amountWithdrawn);
            }
        }
    }

    /// @notice Calculates how much the rebalance should repay or borrow
    /// @return shouldBorrow indicates if we should repay or borrow in order to meet the targetThreshold
    /// @return calculatedAmount calculated amount
    /// @return actionableAmount amount, but further adjusted to constraints
    function calcRebalance()
        internal
        view
        returns (bool shouldBorrow, uint256 calculatedAmount, uint256 actionableAmount)
    {
        uint256 targetBorrow_ = HealthFactorCalculator.targetBorrow(
            activeLenderStrategy,
            supplyUnderlying,
            borrowUnderlying,
            targetThreshold,
            ILenderStrategy(activeLenderStrategy).supplyBalance()
        );

        uint256 totalBorrowed = ILenderStrategy(activeLenderStrategy).borrowBalance();
        if (totalBorrowed <= targetBorrow_) {
            // borrow
            shouldBorrow = true;
            calculatedAmount = targetBorrow_ - totalBorrowed;
            actionableAmount = calculatedAmount;

            uint256 availableLimit = IFarmDispatcher(activeFarmStrategy).availableLimit();
            /// @dev Limit borrowing to as much as we can deposit into the farm
            if (actionableAmount > availableLimit) {
                actionableAmount = availableLimit;
            }

            /// @dev Limit borrowing to lender available liquidity
            availableLimit = ILenderStrategy(activeLenderStrategy).availableBorrowLiquidity();
            if (actionableAmount > availableLimit) {
                actionableAmount = availableLimit;
            }
        } else {
            // repay
            calculatedAmount = totalBorrowed - targetBorrow_;
            actionableAmount = calculatedAmount;

            uint256 vaultBorrows = debtToken.balanceOf(address(this));
            /// @dev Limit repayment up to the vault's debt balance
            if (calculatedAmount > vaultBorrows) {
                actionableAmount = vaultBorrows;
            }
        }
    }
}
