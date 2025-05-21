// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../../base/VaultStorage.sol";
import "../../../../../libraries/utils/CommitMath.sol";
import "../../../../../libraries/types/CommonTypes.sol";
import "../../../../../libraries/uniswap-v3/TransferHelper.sol";

import "../../../../../interfaces/internal/strategy/swap/ISwapStrategy.sol";
import "../../../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import "../../../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";
import "../../../../../interfaces/internal/vault/extensions/supply-loss/ISupplyLossManager.sol";

/**
 * @title SupplyLossManager
 * @dev Contract responsible for dealing with supply loss (typically originated from a vault liquidation)
 * @dev Note! SuplyLossVault storage should be inline with SupplyLossManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

contract SupplyLossManager is VaultStorage, ISupplyLossManager {
    /// @notice SupplyLoss the state of the vault at a time of supply loss, allowing distribution of
    /// supply and debt reductions to users and adjusting vault balance (especially where the vault was actively farming).
    /// Adds a new supply loss snapshot to the list of snapshots.
    /// Resets internal balances used to track interest in both tokens and lender strategy
    function snapshotSupplyLoss() external override {
        if (ILenderStrategy(activeLenderStrategy).hasSupplyLoss()) {
            // Proceed is there is a supply loss with the lender strategy
            SupplyLossTypes.SupplyLoss memory snapshot;
            CommonTypes.SnapshotType memory snapshotType;
            snapshotType.id = supplyLossStorage.supplyLosses.length;
            snapshotType.kind = uint256(CommonTypes.SnapshotClass.SupplyLoss);

            // Get supplyLoss, borrowLoss and fee from the lending strategy
            (snapshot.supplyLossAtSnapshot, snapshot.borrowLossAtSnapshot, snapshot.fee) = ILenderStrategy(
                activeLenderStrategy
            ).preSupplyLossSnapshot();

            // Get borrowIndex and borrowBalanceAtSnapshot from the borrow token
            (snapshotType.borrowIndex, snapshot.borrowBalanceAtSnapshot) = _getTokenState(
                debtToken,
                snapshot.borrowLossAtSnapshot
            );

            // Get supplyIndex and supplyBalanceAtSnapshot from the supply token
            (snapshotType.supplyIndex, snapshot.supplyBalanceAtSnapshot) = _getTokenState(
                supplyToken,
                snapshot.supplyLossAtSnapshot
            );

            // Executes a rebalance, using stored balances prior to supplyLoss
            // 1. Withdraws the vault balance from the farm strategy
            // 2. Swaps the vault balance to the supplyAsset
            // 3. Injects the vault balance into the active lending strategy
            // 4. Repays the active lending strategy as much as possible
            snapshot = _reconcileBalances(snapshotType.borrowIndex, snapshot);

            // Reset token state
            debtToken.setInterestIndex(snapshotType.borrowIndex);
            supplyToken.setInterestIndex(snapshotType.supplyIndex);

            // Reset internal lending strategy balances
            ILenderStrategy(activeLenderStrategy).resetPrincipal(
                ILenderStrategy(activeLenderStrategy).supplyBalance(),
                ILenderStrategy(activeLenderStrategy).borrowBalance()
            );

            // Update global variables
            supplyLossStorage.supplyLosses.push(snapshot);

            snapshots.push(snapshotType);
            // Commit the vault snapshot
            userSnapshots[address(this)] = snapshots.length;

            emit SupplyLossSnapshot(snapshots.length - 1);
        }
    }

    /// @notice Based on the loss return the balanceAtIndex and interestIndex
    /// @param token Interest token to obtain the details for
    /// @param loss Amount of loss incurred
    /// @return interestIndex In case of loss the last stored index or accumulate the new interest and return the current one
    /// @return balanceAtIndex In case of loss the last stored balance or accumulate the new interest and return the current one
    function _getTokenState(IInterestToken token, uint256 loss) internal view returns (uint256, uint256) {
        if (loss > 0) {
            return (token.interestIndex(), token.storedTotalSupply());
        }

        // Gracefully handle edge case where the vault loss has since been repaid through interest
        // @dev this could happen if the vault was liquidated for a small amount and no snapshot taken for a while
        return (token.calcNewIndex(), token.totalSupply());
    }

    /// @notice simulate the outcome of a rebalance should it happen before supply loss was triggered
    /// This simulation enables distribution of supplyLoss and debtLoss to users fairly
    /// @param borrowIndex Index to accumulate interest to
    /// @param snapshot SupplyLoss data containing required properties
    /// @return snapshot Updated snapshot data
    function _reconcileBalances(
        uint256 borrowIndex,
        SupplyLossTypes.SupplyLoss memory snapshot
    ) internal returns (SupplyLossTypes.SupplyLoss memory) {
        // Calculate vault debtToken balance at time of supplyLoss snapshot
        uint256 vaultBorrowsAtSnapshot = Utils.calcBalanceAtIndex(
            debtToken.balanceStored(address(this)),
            debtToken.userIndex(address(this)),
            borrowIndex
        );

        // Deal with rounding errors gracefully
        // @dev needed in case only the vault has borrowed
        if (snapshot.borrowBalanceAtSnapshot < vaultBorrowsAtSnapshot) {
            vaultBorrowsAtSnapshot = snapshot.borrowBalanceAtSnapshot;
        }

        // Withdraw any amount borrowed by the vault from the farm strategy
        (uint256 withdrawn, uint256 withdrawShortage) = _withdrawVaultBorrows(vaultBorrowsAtSnapshot, borrowIndex);

        snapshot.withdrawShortage = withdrawShortage;

        // Calculate how much of vault farm loan was repaid (during liquidation)
        // Swap this amount to the supplyAsset and inject into active lending strategy
        (uint256 vaultWindfall, uint256 amountOut, uint256 injectionFee) = _injectVaultWindfall(
            withdrawn,
            vaultBorrowsAtSnapshot,
            snapshot.borrowLossAtSnapshot,
            snapshot.borrowBalanceAtSnapshot
        );

        // Update the injection fee so it can be distributed correctly
        amountOut += injectionFee;
        snapshot.fee += injectionFee;

        if (snapshot.supplyLossAtSnapshot >= amountOut) {
            // Reduce the supply loss by the amount that has been re-deposited
            snapshot.supplyLossAtSnapshot -= amountOut;
        } else {
            // In case the amount being re-deposited exceeds the amount of supply lost
            // the difference is considered a profit & supplyLossAtSnapshot is set to 0
            snapshot.supplyLossProfit = amountOut - snapshot.supplyLossAtSnapshot;
            snapshot.supplyLossAtSnapshot = 0;
        }

        // Catch the case where the vault is the only borrower (e.g. no users have borrowed)
        // In this case we distribute the supplyLoss to all users equally
        if (vaultBorrowsAtSnapshot == snapshot.borrowBalanceAtSnapshot) {
            snapshot.fee += snapshot.supplyLossAtSnapshot;
            snapshot.supplyLossAtSnapshot = 0;
        }

        // Exclude vaultWindfall as they have been accounted in the supply loss by depositing into the lender
        snapshot.borrowLossAtSnapshot -= vaultWindfall;
        // Exclude vaultBorrows from the snapshot as they have been accounted for
        snapshot.borrowBalanceAtSnapshot -= (vaultBorrowsAtSnapshot - withdrawShortage);

        // Repay as much of the vault lending strategy debt as possible:
        // * `withdrawn - vaultWindfall` is amount of the vault farm loan withdrawn less the amount swapped to supplyAsset
        // * `vaultBorrowsAtSnapshot - vaultWindfall` is the amount of the vault farm loan less the amount swapped to the supplyAsset
        _repayVaultRemaining(withdrawn - vaultWindfall, vaultBorrowsAtSnapshot - vaultWindfall);

        return snapshot;
    }

    /// @notice Withdraw the vaults balance from the farm strategy
    /// @param vaultBorrows Amount to be withdrawn in borrowToken
    /// @param borrowIndex borrowIndex to use when setting the vaults debtToken balance
    /// @return withdrawn Amount withdrawn from the farm strategy in borrowToken
    /// @return farmLoss Loss in case the farm strategy is not able to provide the requested vault balance amount
    function _withdrawVaultBorrows(
        uint256 vaultBorrows,
        uint256 borrowIndex
    ) internal returns (uint256 withdrawn, uint256 farmLoss) {
        // Limit withdraw by excluding previously accumulated rewards
        uint256 toWithdraw = _calcMaxToWithdrawn(IFarmDispatcher(activeFarmStrategy).balance(), vaultBorrows);

        // Withdraw available funds from the farm strategy
        withdrawn = IFarmDispatcher(activeFarmStrategy).withdraw(toWithdraw);

        if (withdrawn < vaultBorrows) {
            // Consider the missing amount as a loss to allow for distribution amoungst users
            farmLoss = vaultBorrows - withdrawn;
        }

        // Any possible farm loss will be accounted through lower decrease in the supply loss
        // Update vault balance in the debtToken to zero (reflecting that the maximum amount was withdrawn)
        debtToken.setBalance(address(this), 0, borrowIndex);

        emit WithdrawVaultBorrows(withdrawn, vaultBorrows);
    }

    function _calcMaxToWithdrawn(uint256 totalBalance, uint256 vaultBorrows) internal view returns (uint256) {
        uint256 asideFunds = harvestStorage.realUncommittedEarnings +
            harvestStorage.vaultReserve +
            harvestStorage.realClaimableEarnings;

        if (totalBalance > asideFunds) {
            totalBalance -= asideFunds;
        } else {
            return 0;
        }

        // Limit up to the vault's borrow balance that we want to repay
        if (totalBalance > vaultBorrows) {
            totalBalance = vaultBorrows;
        }

        return totalBalance;
    }

    /// @notice VaultWindfall is the amount of the vault farm loan that was repaid (during vault liquidation)
    /// For fair distribution we swap this to increase the lender supply balance
    /// @param withdrawn Amount withdrawn from the farmStrategy (in borrowAsset)
    /// @param vaultBorrows Debt balance of the vault at the time of the supplyLoss (in borrowAsset)
    /// @param borrowLossAtSnapshot Total borrow loss at supplyLoss - used to calculate vault loss (in borrowAsset)
    /// @param borrowBalanceAtSnapshot Total debt in the lender strategy at supplyLoss (in borrowAsset)
    /// @return vaultWindfall Amount to be recognised as vaultWindfall (in supplyAsset)
    /// @return amountOut Amount deposited in lendingStrategy (adjusted for slippage and deposit fees) (in supplyAsset)
    /// @return injectionFee Fee in supplyAsset of making an exchange and deposit (in supplyAsset)
    function _injectVaultWindfall(
        uint256 withdrawn,
        uint256 vaultBorrows,
        uint256 borrowLossAtSnapshot,
        uint256 borrowBalanceAtSnapshot
    ) internal returns (uint256 vaultWindfall, uint256 amountOut, uint256 injectionFee) {
        // Calculate vaultWindfall: this is the amount of the vault farm loan that was repaid (during vault liquidation)
        vaultWindfall = CommitMath.calcBorrowAccountLoss(vaultBorrows, borrowLossAtSnapshot, borrowBalanceAtSnapshot);

        // Calculate vaultWindfall: Limit vaultWindfall to how much was actually withdrawn from the farmStrategy
        if (vaultWindfall >= withdrawn) {
            vaultWindfall = withdrawn;
        }

        // Swap vaultWindfall -> supplyAsset: Approve swapStratey to spend vaultWindfall
        TransferHelper.safeApprove(borrowUnderlying, swapStrategy, vaultWindfall);

        // Swap vaultWindfall -> supplyAsset: Calculate expected amount to receive after swap
        uint256 expectedAmountOut = ISwapStrategy(swapStrategy).getMinimumAmountOut(
            borrowUnderlying,
            supplyUnderlying,
            vaultWindfall,
            0
        );

        // Swap vaultWindfall -> supplyAsset: Swap vaultWindfall to supply asset
        amountOut = ISwapStrategy(swapStrategy).swapInBase(borrowUnderlying, supplyUnderlying, vaultWindfall);

        // Swap vaultWindfall -> supplyAsset: Calculate slippage costs
        if (expectedAmountOut > amountOut) {
            injectionFee = expectedAmountOut - amountOut;
        }

        // Deposit vaultWindfall: Transfer vaultWindfall (swapped to supplyAsset) with activeLenderStrategy
        TransferHelper.safeTransfer(supplyUnderlying, activeLenderStrategy, amountOut);

        // Deposit vaultWindfall: Calculate expected balance after deposit
        uint256 expectedBalance = ILenderStrategy(activeLenderStrategy).supplyBalance() + amountOut;

        // Deposit vaultWindfall: Deposit with lender
        ILenderStrategy(activeLenderStrategy).deposit(amountOut);

        // Deposit vaultWindfall: Calculate deposit fees (if any)
        uint256 supplyBalanceAfter = ILenderStrategy(activeLenderStrategy).supplyBalance();

        if (expectedBalance >= supplyBalanceAfter) {
            // Calculate how much less than expected was received
            uint256 diff = expectedBalance - supplyBalanceAfter;
            amountOut -= diff;
            injectionFee += diff;
        } else {
            // Calculate how much more than expected was received
            uint256 diff = supplyBalanceAfter - expectedBalance;
            if (diff > injectionFee) {
                amountOut += diff - injectionFee;
                injectionFee = 0;
            } else {
                injectionFee -= diff;
            }
        }

        emit InjectVaultWindfall(vaultWindfall, expectedAmountOut, amountOut, injectionFee);
    }

    /// @notice Repay the lender as much as possible from the vaultBorrows
    /// @param withdrawn Amount withdrawn from the farmStrategy (less vaultWindfall) (in borrowAsset)
    /// @param vaultBorrowsRemaining Amount to be repaid (in borrowAsset)
    function _repayVaultRemaining(uint256 withdrawn, uint256 vaultBorrowsRemaining) internal {
        // Limit amount to repay to the amount available (after withdraw and vaultWindfall processing)
        if (vaultBorrowsRemaining >= withdrawn) {
            vaultBorrowsRemaining = withdrawn;
        }

        // Limit the amount to repay to the balance of the vault
        uint256 maxBalance = ILenderStrategy(activeLenderStrategy).borrowBalance();

        if (vaultBorrowsRemaining > maxBalance) {
            // Transfer back excess balance to farm strategy
            TransferHelper.safeTransfer(borrowUnderlying, activeFarmStrategy, vaultBorrowsRemaining - maxBalance);
            vaultBorrowsRemaining = maxBalance;
        }

        // Repay the lender strategy
        TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, vaultBorrowsRemaining);
        ILenderStrategy(activeLenderStrategy).repay(vaultBorrowsRemaining);

        emit RepayVaultRemaining(vaultBorrowsRemaining, maxBalance);
    }
}
