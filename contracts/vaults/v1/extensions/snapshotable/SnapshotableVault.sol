// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../base/InterestVault.sol";
import "./harvest/HarvestableVault.sol";
import "./supply-loss/SupplyLossVault.sol";
import "../../../../libraries/utils/CommitMath.sol";
import "../../../../interfaces/internal/vault/extensions/snapshotable/ISnapshotableVault.sol";

/**
 * @title SnapshotableVaultV1
 * @dev Proxy forwarding supply loss and harvest processes to SnapshotableManager
 * @dev Also handles the configuration of the different parameters
 * @dev Note! The snapshot vault storage should be inline with SnapshotableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

abstract contract SnapshotableVaultV1 is
    InterestVault,
    ProxyExtension,
    HarvestableVaultV1,
    SupplyLossVaultV1,
    ISnapshotableVaultV1
{
    /// @notice Update the user's position for all uncomitted snapshots up to now.
    /// @notice It is payable because the 'deposit' function is payable
    /// @param account User wallet address
    /// @return numberOfSnapshots total number of snapshots committed
    function updatePosition(address account) public payable override returns (uint256) {
        _updateInterest();

        return
            abi.decode(
                _exec(snapshotManager, abi.encodeWithSelector(ISnapshotableManager.updatePosition.selector, account)),
                (uint256)
            );
    }

    /// @notice Update the user's position for all uncomitted snapshots up to speicified id.
    /// @param account User wallet address
    /// @param snapshotId Index the user to be commited to
    /// @return numberOfSnapshots total number of snapshots committed
    function updatePositionTo(address account, uint256 snapshotId) external override returns (uint256) {
        _updateInterest();

        return
            abi.decode(
                _exec(
                    snapshotManager,
                    abi.encodeWithSelector(ISnapshotableManager.updatePositionTo.selector, account, snapshotId)
                ),
                (uint256)
            );
    }

    /// @notice Update of one or more users' positions at batch
    /// @param accounts User addresses
    /// @return numberOfSnapshots total number of snapshots committed
    function updatePositions(address[] calldata accounts) public override returns (uint256) {
        _updateInterest();

        return
            abi.decode(
                _exec(snapshotManager, abi.encodeWithSelector(ISnapshotableManager.updatePositions.selector, accounts)),
                (uint256)
            );
    }

    /// @notice Returns user supply and borrow positions up to the specified snapshot in the vault
    ///         accounting for all the uncommited snapshots
    /// @param account User wallet address
    /// @param snapshotId calculate up to this snapshot id
    /// @return commit User commit data
    function calcCommitUser(
        address account,
        uint256 snapshotId
    ) external view override returns (HarvestTypes.UserCommit memory commit) {
        if (ILenderStrategy(activeLenderStrategy).hasSupplyLoss()) {
            revert IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED();
        }

        if (snapshotId > snapshots.length) {
            snapshotId = snapshots.length;
        }

        (commit, ) = CommitMath.calcCommit(
            address(this),
            account,
            supplyToken,
            debtToken,
            userSnapshots[account],
            snapshotId
        );
    }

    /// @notice Add supply in the lender provider directly to cover supply shortage
    /// @param targetTotalSupply the total supply we aim to have after injection
    function injectSupply(uint256 targetTotalSupply, uint256 atIndex, address funder) external override onlyOwner {
        if (ILenderStrategy(activeLenderStrategy).hasSupplyLoss()) {
            revert IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED();
        }

        _exec(
            snapshotManager,
            abi.encodeWithSelector(ISnapshotableManager.injectSupply.selector, targetTotalSupply, atIndex, funder)
        );
    }

    /// @notice Modify the snapshot configuration
    /// @param config configuration to update to
    function setSnapshotableConfig(VaultTypes.SnapshotableConfig memory config) external onlyOwner {
        if (config.reserveFactor > 1e18) {
            // 1e18 represents a 100%. reserveFactor is in percentage
            revert HV_V1_RESERVE_FACTOR_OUT_OF_RANGE();
        }
        harvestStorage.reserveFactor = config.reserveFactor;
        snapshotManager = config.snapshotableManager;
    }

    /// @notice Get the current snapshotable configuration
    /// @return snapshotableConfig details
    function getSnapshotableConfig() external view override returns (address, uint256) {
        return (snapshotManager, harvestStorage.reserveFactor);
    }

    /// @notice Returns the number of snapshots in the system
    function totalSnapshots() external view override returns (uint256) {
        return snapshots.length;
    }

    /// @notice Returns a snapshot by an id
    function getSnapshot(uint256 id) external view override returns (CommonTypes.SnapshotType memory) {
        return snapshots[id];
    }
}
