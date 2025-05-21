// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./Utils.sol";
import "../types/CommonTypes.sol";
import "../types/HarvestTypes.sol";
import "../types/SupplyLossTypes.sol";
import "../../interfaces/internal/vault/IVaultCore.sol";
import "../../interfaces/internal/tokens/IInterestToken.sol";
import "../../interfaces/internal/vault/extensions/harvestable/IHarvestableVault.sol";

/**
 * @title CommitMath
 * @notice A helper for calculating user positions from harvests & vault liqudiation
 * @author Altitude Labs
 **/

library CommitMath {
    /// @notice Calculates debt and supply positions after harvest & supply loss snapshots have happened
    /// @param vault Address of the vault to be able to query
    /// @param account Address to calculate the commit for
    /// @param supplyToken Address of the supply token to query
    /// @param debtToken Address of the borrow token to query
    /// @param userLastSnapshot The id of the users last snapshot
    /// @param totalSnapshots The snapshot id to calculate the commit up to (typically totalSnapshots)
    /// @return commit User commit data, detailing adjustments to the users position
    /// @return numOfSnapshots Number of snapshots being commited
    function calcCommit(
        address vault,
        address account,
        IInterestToken supplyToken,
        IInterestToken debtToken,
        uint256 userLastSnapshot,
        uint256 totalSnapshots
    ) external view returns (HarvestTypes.UserCommit memory commit, uint256 numOfSnapshots) {
        // Get the user's harvest data
        HarvestTypes.UserHarvestData memory userData = IVaultCoreV1(vault).getUserHarvest(account);

        // Get the user's commit data
        commit = HarvestTypes.UserCommit(
            IVaultCoreV1(vault).getHarvest(userData.harvestId).blockNumber,
            userData.harvestId,
            userData.claimableEarnings,
            userData.harvestJoiningBlock,
            userData.uncommittedEarnings,
            userData.vaultReserveUncommitted,
            CommonTypes.UserPosition(
                supplyToken.userIndex(account),
                supplyToken.balanceStored(account),
                debtToken.userIndex(account),
                debtToken.balanceStored(account)
            )
        );

        // Calculate the number of snapshots to be committed
        numOfSnapshots = totalSnapshots - userLastSnapshot;

        // If the user has not been snapshotted yet, we need to calculate the
        // user's commit from their last snapshot to the specified snapshot
        if (userLastSnapshot < totalSnapshots) {
            uint256 decimals = 10 ** supplyToken.decimals();
            CommonTypes.SnapshotType memory snapshot;

            // Loop through snapshots to calculate the users latest position
            for (; userLastSnapshot < totalSnapshots; userLastSnapshot++) {
                // Get the specific snapshot
                snapshot = IVaultCoreV1(vault).getSnapshot(userLastSnapshot);

                // Accumulate interest up to the snapshot indicies
                commit.position = _accumulateInterest(commit.position, snapshot.supplyIndex, snapshot.borrowIndex);

                // Apply each snapshot to the users position
                if (snapshot.kind == uint256(CommonTypes.SnapshotClass.Harvest)) {
                    // Calculate users commit from harvest
                    commit = _calculateHarvestCommit(decimals, commit, IVaultCoreV1(vault).getHarvest(snapshot.id));
                } else {
                    // Calculate users commit from supply loss
                    commit.position = _calculateSupplyLossCommit(
                        commit.position,
                        IVaultCoreV1(vault).getSupplyLossSnapshot(snapshot.id)
                    );
                }
            }
        }
    }

    /// @notice Accumulate interest up to a given snapshot
    /// @param position users position at point of accumulation
    /// @param supplyIndex The supply index to accumulate to
    /// @param borrowIndex The borrow index to accumulate to
    /// @return position Updated user position
    function _accumulateInterest(
        CommonTypes.UserPosition memory position,
        uint256 supplyIndex,
        uint256 borrowIndex
    ) internal pure returns (CommonTypes.UserPosition memory) {
        // Accumulate supply interest
        position.supplyBalance = Utils.calcBalanceAtIndex(position.supplyBalance, position.supplyIndex, supplyIndex);

        // Accumulate borrow interest
        position.borrowBalance = Utils.calcBalanceAtIndex(position.borrowBalance, position.borrowIndex, borrowIndex);

        // Update indicies
        position.supplyIndex = supplyIndex;
        position.borrowIndex = borrowIndex;

        return position;
    }

    /// @notice Calculates user debt and supply positions at time of a harvest snapshot
    /// @param decimals Token decimals for conversion
    /// @param commit User commit data prior to the harvest snapshot
    /// @param harvestSnapshot Harvest snapshot data
    /// @return commit Updated user commit data
    function _calculateHarvestCommit(
        uint256 decimals,
        HarvestTypes.UserCommit memory commit,
        HarvestTypes.HarvestData memory harvestSnapshot
    ) internal pure returns (HarvestTypes.UserCommit memory) {
        int256 userHarvestChange;

        // Calculate the user's active assets, representing their contribution to the harvest
        (int256 activeAssets, int256 netActiveAssets) = _userActiveAssets(decimals, commit, harvestSnapshot);

        // Include only users who have activeAssets in distributions
        if (activeAssets > 0) {
            // Calculate the total earnings from the harvest
            // farmNetProceeds = farmEarnings - farmLoss
            int256 farmNetProceeds = int256(harvestSnapshot.farmEarnings) - int256(harvestSnapshot.vaultLoss);

            // Calculate the user's earnings from the harvest
            // userHarvestChange = (activeAssets * farmNetProceeds) / vaultActiveAssets
            userHarvestChange = (activeAssets * farmNetProceeds) / int256(harvestSnapshot.vaultActiveAssets);
        }

        // If the user has no net active assets (e.g. no active contribution to the harvest)
        // avoid incentivising this by distribute all earnings to the vault reserve
        if (userHarvestChange >= 0 && netActiveAssets < 0) {
            // All earnings go to the vault reserve
            // @dev userHarvestChange is not negative in this if branch
            commit.vaultReserveUncommitted += uint256(userHarvestChange);
            userHarvestChange = 0;
        } else {
            int256 userHarvestRatio = 1e18; // 1e18 represents 100%
            // If the harvest is positive, calculate the user participation ratio
            // To avoid shortfalls, any farmLosses are distributed directly to users
            if (userHarvestChange >= 0) {
                // Calculate the users participation ratio in the harvest
                // userHarvestRatio = participatingBlocks / totalHarvestBlocks
                userHarvestRatio = int256(
                    (1e18 * (harvestSnapshot.blockNumber - commit.userHarvestJoiningBlock)) / // 1e18 represents 100%
                        (harvestSnapshot.blockNumber - commit.blockNumber)
                );
            }

            // Apply the userHarvestRatio to the userHarvestChange
            int256 userHarvestChangeNew = (userHarvestRatio * userHarvestChange) / 1e18; // divided by a 100%

            // Disincentivise users from only participating briefly in harvests
            // Divert earnings for the period the user wasn't fully in the harvest
            commit.vaultReserveUncommitted += uint256(userHarvestChange - userHarvestChangeNew);
            userHarvestChange = userHarvestChangeNew;
        }

        // Distribute vaultLoss to the users
        if (harvestSnapshot.vaultLoss > 0) {
            commit.position.borrowBalance += uint256(-userHarvestChange);
        }

        // If the user has a positive change in harvest earnings, add to their uncommitted earnings
        if (userHarvestChange > 0) {
            commit.userHarvestUncommittedEarnings += uint256(userHarvestChange);
        }

        // Distribute uncommitted earnings loss to the users
        if (harvestSnapshot.uncommittedLossPerc > 0) {
            // Handle user loss part from the uncommitted, round up to prevent underflow
            uint256 uncommittedLoss = (harvestSnapshot.uncommittedLossPerc * commit.userHarvestUncommittedEarnings) /
                1e18;
            if (uncommittedLoss == 0 && commit.userHarvestUncommittedEarnings > 0) {
                uncommittedLoss = 1;
            }
            commit.userHarvestUncommittedEarnings -= uncommittedLoss;
            // Handle vault reserve loss part from the uncommitted, round up to prevent underflow
            uint256 uncommittedReserveLoss = (harvestSnapshot.uncommittedLossPerc * commit.vaultReserveUncommitted) /
                1e18;
            if (uncommittedReserveLoss == 0 && commit.vaultReserveUncommitted > 0) {
                uncommittedReserveLoss = 1;
            }
            commit.vaultReserveUncommitted -= uncommittedReserveLoss;
        }

        // Distribute claimable rewards loss to the users, round up to prevent underflow
        if (harvestSnapshot.claimableLossPerc > 0) {
            uint256 claimableLoss = (harvestSnapshot.claimableLossPerc * commit.userClaimableEarnings) / 1e18;
            if (claimableLoss == 0 && commit.userClaimableEarnings > 0) {
                claimableLoss = 1;
            }
            commit.userClaimableEarnings -= claimableLoss;
        }

        // Update the users commit data
        commit.harvestId = harvestSnapshot.harvestId;
        commit.blockNumber = harvestSnapshot.blockNumber;
        commit.userHarvestJoiningBlock = harvestSnapshot.blockNumber;

        return commit;
    }

    /// @notice Calculate the active assets of the user
    /// @param decimals Tokens decimals for conversion
    /// @param commit User commit data prior to the harvest snapshot
    /// @param harvestSnapshot Harvest snapshot data
    function _userActiveAssets(
        uint256 decimals,
        HarvestTypes.UserCommit memory commit,
        HarvestTypes.HarvestData memory harvestSnapshot
    ) internal pure returns (int256 activeAssets, int256 netActiveAssets) {
        // Convert the users supply balance to the base token (at time of the harvest)
        uint256 userSupplyInBase = ((commit.position.supplyBalance * harvestSnapshot.price) / decimals);

        // Calculate the user's max active assets (at time of the harvest)
        // This represents the maximum amount of assets the user can contribute to the harvest
        uint256 userMaxActiveAssets = (userSupplyInBase * harvestSnapshot.activeAssetsThreshold) / 1e18; // 1e18 represents a 100%. activeAssetsThreshold is a percent

        // Calculate the user's max nondivertable assets (at time of the harvest)
        // This represents the amount of assets the user would typically contribute to the harvest
        uint256 userMaxNondivertableAssets = (userSupplyInBase * harvestSnapshot.divertEarningsThreshold) / 1e18; // 1e18 represents a 100%. divertEarningsThreshold is a percent

        // Calculate the user's borrow balance, adjusted with their claimable earnings (at time of the harvest)
        int256 userBorrowsAdjusted = int256(commit.position.borrowBalance) - int256(commit.userClaimableEarnings);

        // Calculate the user's active assets (at time of the harvest)
        // This represents the maximum amount the user could contribute to the harvest considering their borrow balance
        activeAssets = int256(userMaxActiveAssets) - userBorrowsAdjusted;

        // Calculate the user's net active assets (at time of the harvest)
        // This represents the amount the user would typically contribute to the harvest considering their borrow balance
        netActiveAssets = int256(userMaxNondivertableAssets) - userBorrowsAdjusted;
    }

    /// @notice Distributes supply loss and returns user's debt and supply positions
    /// @param position User position prior to the supply loss snapshot
    /// @param snapshot Supply loss snapshot data
    /// @return newPosition New user commit data
    function _calculateSupplyLossCommit(
        CommonTypes.UserPosition memory position,
        SupplyLossTypes.SupplyLoss memory snapshot
    ) internal pure returns (CommonTypes.UserPosition memory) {
        // Calculate the borrow farm loss for the user
        position.borrowBalance += _distributeWithdrawShortage(snapshot, position.supplyBalance);

        // Calculate the borrow loss for the user
        uint256 borrowLoss = _distributeBorrowLoss(snapshot, position.borrowBalance);

        // Calculate the supply loss and supply recovery for the user
        (uint256 supplyLoss, uint256 supplyRecovery) = _distributeSupplyLoss(
            snapshot,
            position.supplyBalance,
            position.borrowBalance
        );

        // Increase user's supply balance by supplyRecovery
        position.supplyBalance += supplyRecovery;

        // Decrease user's supply balance by supplyLoss
        if (position.supplyBalance > supplyLoss) {
            position.supplyBalance -= supplyLoss;
        } else {
            // In a case of supply shortage to not underflow
            position.supplyBalance = 0;
        }

        // Decrease user's borrow balance by borrowLoss
        if (position.borrowBalance > borrowLoss) {
            position.borrowBalance -= borrowLoss;
        } else {
            // In a case of rounding issues for the last commiter
            position.borrowBalance = 0;
        }

        return position;
    }

    /// @notice Distributes supplyLoss and returns the user supply adjustments
    /// @param snapshot Supply loss snapshot data
    /// @param supplyBalance User's supply balance prior to the supply loss snapshot
    /// @param borrowBalance User's borrow balance prior to the supply loss snapshot
    /// @return supplyLoss The amount of supply loss
    /// @return supplyRecovery The amount of supply recovered (if any)
    function _distributeSupplyLoss(
        SupplyLossTypes.SupplyLoss memory snapshot,
        uint256 supplyBalance,
        uint256 borrowBalance
    ) internal pure returns (uint256 supplyLoss, uint256 supplyRecovery) {
        // Distribute supply loss if the user has a positive supply balance
        if (supplyBalance > 0) {
            if (snapshot.supplyLossProfit > 0) {
                // If there is supplyLossProfit, distribute it to the user proportionally
                supplyRecovery += (supplyBalance * snapshot.supplyLossProfit) / snapshot.supplyBalanceAtSnapshot;
            }

            if (snapshot.supplyLossAtSnapshot + snapshot.fee > 0) {
                // If there are supplyLosses and/or fees, distribute them to the user proportionally
                if (borrowBalance > 0) {
                    // SupplyLoss is distributed to users with borrow balances
                    // Distribute supplyLoss proportionally to the user's borrow balance
                    // @dev we're using rounding to avoid shortfalls
                    supplyLoss = Utils.divRoundingUp(
                        borrowBalance * snapshot.supplyLossAtSnapshot,
                        snapshot.borrowBalanceAtSnapshot
                    );
                }

                // Fees are distributed to all users (fees originate from liquidation incentive, slippage, etc.)
                // Distribute fees proportionally to the user's supply balance
                // @dev we're using rounding to avoid shortfalls
                uint256 feeLoss = Utils.divRoundingUp(supplyBalance * snapshot.fee, snapshot.supplyBalanceAtSnapshot);

                supplyLoss += feeLoss;
            }
        }
    }

    /// @notice Distributes withdraw shortage and returns the user borrow adjustments
    /// @param snapshot Supply loss snapshot data
    /// @param supplyBalance User's supply balance prior to the supply loss snapshot
    /// @return withdrawShortage The amount of withdraw shortage (originating from farming activities)
    function _distributeWithdrawShortage(
        SupplyLossTypes.SupplyLoss memory snapshot,
        uint256 supplyBalance
    ) internal pure returns (uint256 withdrawShortage) {
        // Distribute farmLoss relative to the users supply balance
        // withdraw shortage orginate from farming activities so are distributed to all users
        // @dev we're using rounding to avoid shortfalls
        withdrawShortage = Utils.divRoundingUp(
            supplyBalance * snapshot.withdrawShortage,
            snapshot.supplyBalanceAtSnapshot
        );
    }

    /// @notice Distributes borrowLoss and adjusts returns the user borrow adjustments
    /// @param snapshot Supply loss snapshot data
    /// @param borrowBalance User's borrow balance prior to the supply loss snapshot
    /// @return borrowLoss The amount of borrow loss
    function _distributeBorrowLoss(
        SupplyLossTypes.SupplyLoss memory snapshot,
        uint256 borrowBalance
    ) internal pure returns (uint256 borrowLoss) {
        // Distribute borrowLoss relative to the users borrow balance
        if (borrowBalance > 0 && snapshot.borrowLossAtSnapshot > 0) {
            borrowLoss = (borrowBalance * snapshot.borrowLossAtSnapshot) / snapshot.borrowBalanceAtSnapshot;
        }
    }

    /// @notice Calculates what debt loss to be distributed to a given account from a supply loss
    /// @param balance The current balance of an account
    /// @param borrowLossAtSnapshot The loss at supply loss snapshot
    /// @param borrowBalanceAtSnapshot The borrow balance at supply loss snapshot
    /// @return loss The amount of the loss the account is to receive
    function calcBorrowAccountLoss(
        uint256 balance,
        uint256 borrowLossAtSnapshot,
        uint256 borrowBalanceAtSnapshot
    ) external pure returns (uint256 loss) {
        if (balance > 0) {
            if (balance >= borrowBalanceAtSnapshot) {
                loss = borrowLossAtSnapshot;
            } else {
                loss = Utils.divRoundingUp(balance * borrowLossAtSnapshot, borrowBalanceAtSnapshot);
            }
        }
    }
}
