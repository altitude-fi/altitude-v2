// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../base/VaultStorage.sol";
import "./harvest/HarvestableManager.sol";
import "./supply-loss/SupplyLossManager.sol";
import "../../../../libraries/utils/CommitMath.sol";
import "../../../../libraries/utils/Utils.sol";
import "../../../../interfaces/internal/access/IIngress.sol";
import "../../../../interfaces/internal/vault/extensions/snapshotable/ISnapshotableManager.sol";

/**
 * @title SnapshotableManager
 * @dev Contract responsible for making snapshots of the vault's state
 * @dev Note! The snapshot vault storage should be inline with SnapshotableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

contract SnapshotableManager is VaultStorage, HarvestableManager, SupplyLossManager, ISnapshotableManager {
    modifier onlyNotVault(address account) {
        if (account == address(this)) {
            revert HM_V1_INVALID_COMMIT();
        }
        _;
    }

    /// @notice Update the user's position for all uncomitted harvests and supply losses up to now.
    /// @notice It is payable because of deposit is payable
    /// @param account User wallet address
    function updatePosition(
        address account
    ) public payable override onlyNotVault(account) returns (uint256 numberOfSnapshots) {
        // In case the user is operating with the protocol for the first time ever
        if (
            supplyToken.balanceStored(account) == 0 &&
            debtToken.balanceStored(account) == 0 &&
            harvestStorage.userHarvest[account].claimableEarnings == 0
        ) {
            // User has no assets that can make him part of harvests. Just advance the harvest id.
            harvestStorage.userHarvest[account].harvestId = harvestStorage.harvests.length - 1;

            userSnapshots[account] = snapshots.length;
            return 0;
        }

        HarvestTypes.UserCommit memory commit;
        (commit, numberOfSnapshots) = _commitUser(account, snapshots.length);
        userSnapshots[account] = snapshots.length;

        _storeCommit(account, commit);
        _repayLoan(account, commit);
    }

    /// @notice Update the user's position for all uncomitted harvests and supply losses up to speicified id.
    /// @param account User wallet address
    /// @param snapshotId Index the user to be commited to.
    /// @dev To update to the latest commit, simply provide snapshotId bigger than snapshots.length
    function updatePositionTo(
        address account,
        uint256 snapshotId
    ) external override onlyNotVault(account) returns (uint256 numberOfSnapshots) {
        if (snapshotId >= snapshots.length) {
            numberOfSnapshots = updatePosition(account);
        } else {
            HarvestTypes.UserCommit memory commit;
            (commit, numberOfSnapshots) = _commitUser(account, snapshotId);
            userSnapshots[account] = snapshotId;

            _storeCommit(account, commit);
        }
    }

    /// @notice Update of one or more users' positions at batch
    /// @param accounts User addresses
    /// @return numberOfSnapshots total number of harvests and supply losses committed
    function updatePositions(address[] calldata accounts) external override returns (uint256 numberOfSnapshots) {
        for (uint256 i; i < accounts.length; ++i) {
            numberOfSnapshots += updatePosition(accounts[i]);
        }
    }

    /// @notice Commit the user's calculations for all uncomitted harvests and supply losses up to now.
    /// @param account User wallet address
    /// @param snapshotId Index the user to be commited to
    /// @return commit data calculated on commit
    /// @return numOfSnapshots number of harvests and supply losses committed
    function _commitUser(
        address account,
        uint256 snapshotId
    ) internal returns (HarvestTypes.UserCommit memory commit, uint256 numOfSnapshots) {
        IIngress(ingressControl).validateCommit();

        (commit, numOfSnapshots) = CommitMath.calcCommit(
            address(this),
            account,
            supplyToken,
            debtToken,
            userSnapshots[account],
            snapshotId
        );

        supplyToken.setBalance(account, commit.position.supplyBalance, commit.position.supplyIndex);
        debtToken.setBalance(account, commit.position.borrowBalance, commit.position.borrowIndex);

        // If not a partial commit, then update the user's position to account for the latest interest
        if (snapshotId == snapshots.length) {
            (commit.position.supplyBalance, commit.position.supplyIndex) = supplyToken.snapshotUser(account);
            (commit.position.borrowBalance, commit.position.borrowIndex) = debtToken.snapshotUser(account);
        }

        emit UserCommit(
            account,
            commit.position.supplyIndex,
            commit.position.supplyBalance,
            commit.position.borrowIndex,
            commit.position.borrowBalance,
            commit.userHarvestUncommittedEarnings
        );
    }

    /// @notice Add supply in the lender provider directly to cover supply shortage
    /// @dev Supply shortage could occur when committing a user for supply loss and
    /// @dev there is more loss than his supply balance. In that case the remaining
    /// @dev loss will affect the last user to not be able to withdraw his deposited amount.
    /// @dev For that reason the admins are responsible to top-up the supply directly to the lender
    /// @dev provider to not affect the interest index.
    /// @dev In case of a deposit fee or rewards they are getting distributed among the users by index
    /// @param amountToInject supply amount to be injected
    /// @param atIndex index we calculated amountToInject at
    function injectSupply(uint256 amountToInject, uint256 atIndex, address funder) external override {
        // Note, if we are here, hasSupplyLoss() == false

        // Interest accrues between supply shortage calculation and supply injection
        amountToInject = Utils.calcBalanceAtIndex(amountToInject, atIndex, supplyToken.calcNewIndex());

        // Note that for ETH vaults we work with WETH
        TransferHelper.safeTransferFrom(supplyUnderlying, funder, activeLenderStrategy, amountToInject);
        // interestIndex update must exclude the injected supply
        debtToken.snapshot();
        supplyToken.snapshot();
        // Deposit will update the stored lender borrow and supply balance
        uint256 actualInjected = ILenderStrategy(activeLenderStrategy).deposit(amountToInject);
        // And now the new balance is at the previously calculated index,
        // so the injected supply isn't seen and distributed as interest

        if (actualInjected > amountToInject) {
            // Distribute the deposit rewards among the users
            uint256 indexIncrease = supplyToken.calcIndex(
                supplyToken.totalSupply() - (actualInjected - amountToInject)
            );
            supplyToken.setInterestIndex(indexIncrease);
        }

        emit InjectSupply(actualInjected, amountToInject);
    }
}
