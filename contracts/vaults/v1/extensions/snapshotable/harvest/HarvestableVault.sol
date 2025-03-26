// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../../base/InterestVault.sol";
import "./../../../base/JoiningBlockVault.sol";
import "../../../../../common/ProxyExtension.sol";
import "../../../../../libraries/types/HarvestTypes.sol";
import "../../../../../interfaces/internal/access/IIngress.sol";
import "../../../../../interfaces/internal/vault/extensions/IVaultExtensions.sol";
import "../../../../../interfaces/internal/vault/extensions/harvestable/IHarvestableVault.sol";
import "../../../../../interfaces/internal/vault/extensions/harvestable/IHarvestableManager.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title HarvestableVault
 * @dev Proxy forwarding groomable processes to HarvestableManager
 * @dev Also handles the configuration of the harvestable parameters
 * @dev Note! The harvest manager storage should be inline with HarvestableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

abstract contract HarvestableVaultV1 is InterestVault, JoiningBlockVault, ProxyExtension, IHarvestableVaultV1 {
    /// @notice Forwards the execution to the snapshotManager
    function harvest(uint256 price) external override onlyOwner {
        _updateInterest();

        _exec(snapshotManager, abi.encodeWithSelector(IHarvestableManager.harvest.selector, price));
    }

    /// @notice Deposit funds directly into the farm to cover any rewards deficit
    function injectBorrowAssets(uint256 amount) external virtual override onlyOwner {
        _exec(snapshotManager, abi.encodeWithSelector(IHarvestableManager.injectBorrowAssets.selector, amount));
    }

    /// @notice Claim rewards that user has earned from harvests
    function claimRewards(uint256 amountRequested) external override nonReentrant returns (uint256 amountSent) {
        IVaultExtensions(address(this)).updatePosition(msg.sender);

        amountSent = abi.decode(
            _exec(snapshotManager, abi.encodeWithSelector(IHarvestableManager.claimRewards.selector, amountRequested)),
            (uint256)
        );

        IIngress(ingressControl).validateClaimRewards(msg.sender, amountSent);
    }

    /// @notice returns account's claimable rewards accounting for farm loss if any
    /// @param account account to return rewards for
    /// @return claimableAmount account's claimable rewards accounting for farm loss if any
    function claimableRewards(address account) external view override returns (uint256) {
        (
            uint256 debtBalance,
            uint256 earnings, // incomming uncommitted earnings
            uint256 claimableAmount // commited earnings so far
        ) = debtToken.balanceOfDetails(account);

        // In case one could not have any claimable earnings yet, but to have in the next commit.
        // We should account for them as well.
        if (debtBalance < earnings) {
            claimableAmount += earnings - debtBalance;
            debtBalance = 0;
        } else {
            debtBalance = debtBalance - earnings;
        }

        // Handle farm loss case
        if (debtBalance > 0 && claimableAmount > 0) {
            if (debtBalance > claimableAmount) {
                return 0;
            } else {
                return claimableAmount - debtBalance;
            }
        }

        return claimableAmount;
    }

    /// @notice Withdraw collected fees from harvesting to owner
    /// @param receiver account receiving the withdraw
    /// @param amount amount to withdraw from the reserve
    function withdrawReserve(address receiver, uint256 amount) external override onlyOwner returns (uint256) {
        return
            abi.decode(
                _exec(
                    snapshotManager,
                    abi.encodeWithSelector(IHarvestableManager.withdrawReserve.selector, receiver, amount)
                ),
                (uint256)
            );
    }

    /// @return reserveAmount vault reserve amount
    function reserveAmount() external view override returns (uint256) {
        return IERC20(borrowUnderlying).balanceOf(address(this)) + harvestStorage.vaultReserve;
    }

    /// @param id The harvest id
    /// @return harvestData Data from the specified harvest
    function getHarvest(uint256 id) external view override returns (HarvestTypes.HarvestData memory) {
        return harvestStorage.harvests[id];
    }

    /// @notice Get a count of the number of harvests stored
    /// @return harvestCount a count of harvests
    function getHarvestsCount() external view override returns (uint256) {
        return harvestStorage.harvests.length;
    }

    /// @notice Get a user's harvest data
    /// @param user User address
    /// @return userHarvest data for specified user
    function getUserHarvest(address user) external view override returns (HarvestTypes.UserHarvestData memory) {
        return harvestStorage.userHarvest[user];
    }

    /// @notice Get harvest data
    /// @return realClaimableEarnings real claimable earnings
    /// @return realUncommittedEarnings real uncommited earnings
    /// @return vaultReserve vault reserve
    function getHarvestData()
        external
        view
        override
        returns (uint256 realClaimableEarnings, uint256 realUncommittedEarnings, uint256 vaultReserve)
    {
        return (
            harvestStorage.realClaimableEarnings,
            harvestStorage.realUncommittedEarnings,
            harvestStorage.vaultReserve
        );
    }
}
