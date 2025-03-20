// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./ISnapshotableManager.sol";
import "../harvestable/IHarvestableVault.sol";
import "../supply-loss/ISupplyLossVault.sol";
import "../../../../../libraries/types/VaultTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface ISnapshotableVaultV1 is ISnapshotableManager, IHarvestableVaultV1, ISupplyLossVaultV1 {
    function setSnapshotableConfig(VaultTypes.SnapshotableConfig memory config) external;

    function getSnapshotableConfig() external view returns (address, uint256);

    function calcCommitUser(address account, uint256 snapshotId)
        external
        view
        returns (HarvestTypes.UserCommit memory commit);

    function totalSnapshots() external view returns (uint256);

    function getSnapshot(uint256 id) external view returns (CommonTypes.SnapshotType memory);
}
