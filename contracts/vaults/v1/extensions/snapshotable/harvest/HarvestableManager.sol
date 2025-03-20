// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../../base/VaultStorage.sol";
import "../../../../../libraries/types/HarvestTypes.sol";
import "../../../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import "../../../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";
import "../../../../../interfaces/internal/vault/extensions/harvestable/IHarvestableManager.sol";

/**
 * @title HarvestableManager
 * @dev Contract responsible for harvesting and commiting farmStrategy funds on behalf of users
 * @dev Note! The harvest manager storage should be inline with HarvestableVault
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

contract HarvestableManager is VaultStorage, IHarvestableManager {
    /// @notice Snapshot the state of the vault at a given time, allowing distribution of rewards to users
    /// @dev Adds a new harvest to the list of harvests with updated calculations
    /// @dev We use error codes because critical functionality mustn't fail if harvest() reverts
    function harvest(uint256 price) external virtual override {
        uint256 numberOfHarvests = harvestStorage.harvests.length;
        // Check harvest sequencing and that there is only one harvest per block
        if (block.number <= harvestStorage.harvests[numberOfHarvests - 1].blockNumber) {
            revert HM_V1_BLOCK_ERROR();
        }

        HarvestTypes.HarvestData memory newHarvest;

        // Check the current price isn't lower than required
        // @dev this is to guard against sudden price drops
        newHarvest.price = ILenderStrategy(activeLenderStrategy).getInBase(supplyUnderlying, borrowUnderlying);
        if (newHarvest.price < price) {
            revert HM_V1_PRICE_TOO_LOW();
        }

        uint256 vaultBorrows = debtToken.balanceOf(address(this));

        // Calculate harvest parameters
        newHarvest.vaultActiveAssets = _getVaultActiveAssets(newHarvest.price, vaultBorrows);

        // Check if there are active assets in the vault
        if (newHarvest.vaultActiveAssets == 0) {
            revert HV_V1_HM_NO_ACTIVE_ASSETS();
        }

        // Store harvest
        (
            newHarvest.farmEarnings,
            newHarvest.vaultLoss,
            newHarvest.uncommittedLossPerc,
            newHarvest.claimableLossPerc
        ) = _accountProfitLoss(vaultBorrows);

        newHarvest.blockNumber = block.number;
        newHarvest.harvestId = numberOfHarvests;
        newHarvest.activeAssetsThreshold = liquidationThreshold;
        newHarvest.divertEarningsThreshold = targetThreshold;

        // Update global variables
        harvestStorage.realUncommittedEarnings += newHarvest.farmEarnings;
        harvestStorage.harvests.push(newHarvest);
        snapshots.push(
            CommonTypes.SnapshotType(
                numberOfHarvests,
                uint256(CommonTypes.SnapshotClass.Harvest),
                supplyToken.interestIndex(),
                debtToken.interestIndex()
            )
        );
        userSnapshots[address(this)] = snapshots.length;

        emit Harvested(
            numberOfHarvests,
            newHarvest.farmEarnings,
            newHarvest.vaultLoss,
            newHarvest.uncommittedLossPerc,
            newHarvest.claimableLossPerc
        );
    }

    /// @notice Account for profit & loss
    /// @param vaultBorrows The current borrow balance of the vault
    function _accountProfitLoss(uint256 vaultBorrows)
        internal
        returns (
            uint256 farmProfit,
            uint256 vaultLoss,
            uint256 uncommittedLossPerc,
            uint256 claimableLossPerc
        )
    {
        // Deposit available funds into strategies (for compounding)
        IFarmDispatcher(activeFarmStrategy).dispatch();

        // Calculate profit and loss for harvest period
        uint256 farmLoss;
        (farmProfit, farmLoss) = _calcProfitLoss(vaultBorrows);

        if (farmProfit > 0) {
            // Take protocol income
            if (harvestStorage.reserveFactor > 0) {
                uint256 reserveAmount = (farmProfit * harvestStorage.reserveFactor) / 1e18; // 1e18 represents a 100%. reserveFactor is in percentage
                harvestStorage.vaultReserve += reserveAmount;
                farmProfit -= reserveAmount;
            }
        } else {
            (vaultLoss, uncommittedLossPerc, claimableLossPerc) = _splitFarmLoss(farmLoss, vaultBorrows);
        }
    }

    /// @notice Calculate the permanent loss and profit between two harvests
    /// @param vaultBorrows The current borrow balance of the vault
    /// @return farmProfit The calculated profit
    /// @return farmLoss The calculated loss
    function _calcProfitLoss(uint256 vaultBorrows) internal view returns (uint256 farmProfit, uint256 farmLoss) {
        // Calculate the amount of assets expected in the farm
        // vaultBorrows (vaultBorrows) + uncommittedEarnings (realUncommitted and realClaimable) + vaultReserve
        uint256 farmExpected = vaultBorrows +
            harvestStorage.realUncommittedEarnings +
            harvestStorage.realClaimableEarnings +
            harvestStorage.vaultReserve;

        uint256 farmActual = IFarmDispatcher(activeFarmStrategy).balance();

        // Handle loss which includes
        // 1. vault debt interest
        // 2. farm dispatcher loss
        // 3. (optional) swapping costs
        if (farmExpected > farmActual) {
            farmLoss = farmExpected - farmActual;
        } else {
            farmProfit = farmActual - farmExpected;
        }
    }

    /// @notice Split farm loss among different deposit sources
    /// @param loss The amount of loss to be split
    /// @param vaultBorrows The current borrow balance of the vault
    /// @return vaultLoss Loss part of the vault borrows
    /// @return uncommittedLossPerc Loss part of the uncommitted rewards
    /// @return claimableLossPerc Loss part of the claimable rewards
    function _splitFarmLoss(uint256 loss, uint256 vaultBorrows)
        internal
        returns (
            uint256 vaultLoss,
            uint256 uncommittedLossPerc,
            uint256 claimableLossPerc
        )
    {
        // Settle loss from vaultBorrows
        if (loss > vaultBorrows) {
            // Loss is greater than outstanding vault debt
            // - The vault has no assets to cover the loss.
            // - Vault debt is burned (while the user debt increases)
            // - Loss is reduced by the vault debt
            // - The rest of the loss is distributed
            vaultLoss = vaultBorrows;
            debtToken.burn(address(this), vaultBorrows);
            loss -= vaultBorrows;
        } else {
            debtToken.burn(address(this), loss);
            return (loss, 0, 0);
        }

        // Settle loss from realUncommittedEarnings
        if (loss > harvestStorage.realUncommittedEarnings) {
            loss -= harvestStorage.realUncommittedEarnings;
            uncommittedLossPerc = 1e18; // 100% loss
            harvestStorage.realUncommittedEarnings = 0;
        } else {
            uncommittedLossPerc = (loss * 1e18) / harvestStorage.realUncommittedEarnings;
            harvestStorage.realUncommittedEarnings -= loss;
            return (vaultBorrows, uncommittedLossPerc, 0);
        }

        // Settle loss from real claimable rewards
        if (loss > harvestStorage.realClaimableEarnings) {
            loss -= harvestStorage.realClaimableEarnings;
            claimableLossPerc = 1e18; // 100% loss
            harvestStorage.realClaimableEarnings = 0;
        } else {
            claimableLossPerc = (loss * 1e18) / harvestStorage.realClaimableEarnings;
            harvestStorage.realClaimableEarnings -= loss;
            return (vaultBorrows, uncommittedLossPerc, claimableLossPerc);
        }

        // Settle loss from vaultReserve
        harvestStorage.vaultReserve -= loss;
    }

    /// @notice Calculate the active assets of the vault
    /// @param price The current price of the borrow asset
    /// @param protocolBorrows The amount borrowed by the vault on behalf of users
    /// @return activeAssets The active assets of the vault (or zero if there are no or negative active assets)
    function _getVaultActiveAssets(uint256 price, uint256 protocolBorrows)
        internal
        view
        returns (uint256 activeAssets)
    {
        uint256 vaultUserBorrows;
        uint256 totalBorrowed = debtToken.totalSupply();
        uint256 totalSupplied = supplyToken.totalSupply();

        // Deal with an edge-case where multiple users borrowed and fully repaid leaving only
        // the vault with debtTokens. Its balance (which is the total supply)
        // can be a few wei above the protocolBorrows and cause underflow
        if (totalBorrowed > protocolBorrows) {
            vaultUserBorrows = totalBorrowed - protocolBorrows;
        }

        uint256 vaultSupplyInBase = (totalSupplied * price) / 10**supplyToken.decimals();

        // Calculate active assets at vault level
        activeAssets = ((liquidationThreshold * vaultSupplyInBase) / 1e18) + harvestStorage.realClaimableEarnings; // 1e18 represents a 100%. liquidationThreshold is in percentage

        if (activeAssets > vaultUserBorrows) {
            activeAssets -= vaultUserBorrows;
        } else {
            activeAssets = 0;
        }
    }

    /// @notice Deposit funds directly into the farm to cover any deficit
    /// @param amount The sum of borrow currency to be injected
    function injectBorrowAssets(uint256 amount) external {
        if (amount == 0) {
            revert HM_V1_INVALID_INJECT_AMOUNT();
        }

        // Transfer the funds to the farm dispatcher
        TransferHelper.safeTransferFrom(borrowUnderlying, msg.sender, activeFarmStrategy, amount);

        // Update global variables
        harvestStorage.realUncommittedEarnings += amount;

        emit InjectedBorrowAssets(amount);
    }

    /// @notice Store user's harvest position for the next commits
    /// @param account Account to be handled
    /// @param commit Account's position after last commit
    function _storeCommit(address account, HarvestTypes.UserCommit memory commit) internal {
        uint256 lastHarvestId = harvestStorage.harvests.length - 1;
        HarvestTypes.UserHarvestData storage user = harvestStorage.userHarvest[account];

        user.harvestId = commit.harvestId;
        user.claimableEarnings = commit.userClaimableEarnings;
        user.harvestJoiningBlock = commit.userHarvestJoiningBlock;

        if (lastHarvestId == commit.harvestId) {
            // Reset user's data for the next commit
            user.uncommittedEarnings = 0;
            user.vaultReserveUncommitted = 0;
        } else {
            // Increase user's harvest trackers
            user.uncommittedEarnings = commit.userHarvestUncommittedEarnings;
            user.vaultReserveUncommitted = commit.vaultReserveUncommitted;
        }
    }

    /// @notice Repay user's debt with harvest earnings
    /// @param account Account to be handled
    /// @param commit Account's position after commit
    function _repayLoan(address account, HarvestTypes.UserCommit memory commit) internal {
        // Rewards distribution
        uint256 realUncommittedEarnings = harvestStorage.realUncommittedEarnings;

        // Can the harvest's net earnings completely cover the user's borrow?
        if (commit.position.borrowBalance < commit.userHarvestUncommittedEarnings) {
            // Yes, we fully repay the debt and put the rest in claimable earnings.
            // Transfer user's covered debt (which here means the whole debt) to the vault, turning it into vault active assets.
            _repayDebtWithRewards(account, commit.position.borrowBalance);

            // Make rewards claimable
            uint256 claimableEarnings = commit.userHarvestUncommittedEarnings - commit.position.borrowBalance;
            harvestStorage.userHarvest[account].claimableEarnings += claimableEarnings;
            harvestStorage.realClaimableEarnings += claimableEarnings;
        } else {
            // We will reduce the user debt by the harvest earnings
            _repayDebtWithRewards(account, commit.userHarvestUncommittedEarnings);
        }

        // If vaultReserveUncommitted is bigger than 0
        if (commit.vaultReserveUncommitted > 0) {
            harvestStorage.vaultReserve += commit.vaultReserveUncommitted;
            realUncommittedEarnings -= commit.vaultReserveUncommitted;
        }

        // Update harvest data
        realUncommittedEarnings -= commit.userHarvestUncommittedEarnings;
        harvestStorage.realUncommittedEarnings = realUncommittedEarnings;
    }

    /// @notice Transfer debt from user to vault (when using harvest earnings to reduce debt)
    /// @dev Effectively transfers ownership of *existing* farming assets to the vault.
    /// @param account account to transfer from
    /// @param debtToReduce amount intended for transfer
    function _repayDebtWithRewards(address account, uint256 debtToReduce) internal {
        // To keep farming with the amount we transfer the debt from the user to the vault
        if (debtToReduce > 0) {
            debtToken.vaultTransfer(account, address(this), debtToReduce);
        }
    }

    /// @notice Withdraw collected fees from harvests
    /// @dev Only executable by owner
    /// @param receiver account receiving the withdraw
    /// @param amount amount to withdraw from the reserve
    function withdrawReserve(address receiver, uint256 amount) external override returns (uint256) {
        // What part of it is tokens sitting at the vault contract, the rest would be withdrawn from the farm
        uint256 readyAmount = IERC20(borrowUnderlying).balanceOf(address(this));

        // Part of the vault reserve is at the vault contract and part of it is in the farm
        uint256 vaultReserveTotal = readyAmount + harvestStorage.vaultReserve;

        if (amount > vaultReserveTotal) {
            amount = vaultReserveTotal;
        }

        if (amount > readyAmount) {
            uint256 withdrawn = IFarmDispatcher(activeFarmStrategy).withdraw(amount - readyAmount);

            amount = readyAmount + withdrawn;
            harvestStorage.vaultReserve -= withdrawn;
        }

        TransferHelper.safeTransfer(borrowUnderlying, receiver, amount);

        return amount;
    }

    /// @notice Claim rewards that user has earned from harvests
    /// @param amountRequested Amount to be send to the user
    function claimRewards(uint256 amountRequested) external override returns (uint256 amountSent) {
        // Limit amount to available claimable earnings for user
        uint256 amountTotal = harvestStorage.userHarvest[msg.sender].claimableEarnings;

        // In case a user borrows, then commits, then borrows again, the earnings will cover the first borrow, but
        // will not cover the second one until there is another harvest to commit. So in practice the user will have debt and claimable earnings.
        // In case there is farm loss, the debt of a user is increased.
        // A user having claimable rewards is assumed to not have any debt, but because of the farm loss
        // he would start having debt again. For that reason, the protocol will try on claiming to repay as much as
        // possible of that user's debt based on the amount of claimable earnings.
        /// @dev We can use directly debtToken.balanceOf compared to the claimableRewards function
        /// @dev as we are commiting the user which increases user's claimableEarnings in storage(postHarvest). Whereas in claimableRewards calculation
        /// @dev we are calculating the commit which is not touching the storage(claimableEarnings).
        uint256 debtBalance = debtToken.balanceOf(msg.sender);

        if (amountTotal == 0 || (amountRequested == 0 && debtBalance == 0)) {
            revert HM_V1_CLAIM_REWARDS_ZERO();
        }

        if (debtBalance >= amountTotal) {
            _repayDebtWithRewards(msg.sender, amountTotal);
            debtBalance = amountTotal;
        } else {
            _repayDebtWithRewards(msg.sender, debtBalance);
            if (amountRequested > 0) {
                uint256 amountSendable = amountTotal - debtBalance;
                if (amountRequested > amountSendable) {
                    amountSent = _processClaim(amountSendable);
                } else {
                    amountSent = _processClaim(amountRequested);
                }
            }
            amountTotal = amountSent + debtBalance;
        }

        // Update balances
        harvestStorage.realClaimableEarnings -= amountTotal;
        harvestStorage.userHarvest[msg.sender].claimableEarnings -= amountTotal;

        emit ClaimedRewards(msg.sender, amountTotal, debtBalance);
    }

    /// @notice Transfer rewards for claiming to the owner
    function _processClaim(uint256 claimAmount) internal returns (uint256 actualClaimed) {
        actualClaimed = IFarmDispatcher(activeFarmStrategy).withdraw(claimAmount);

        if (actualClaimed > 0) {
            TransferHelper.safeTransfer(borrowUnderlying, msg.sender, actualClaimed);
        }
    }
}
