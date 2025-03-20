// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./CommonTypes.sol";

/**
 * @title HarvestTypes
 * @notice Harvest storage types
 * @author Altitude Labs
 **/

library HarvestTypes {
    /// @notice track the committable data for a user, detailing incremental adjustements to the user position
    struct UserCommit {
        uint256 blockNumber; // block number of the commit
        uint256 harvestId; // harvest id of the commit
        uint256 userClaimableEarnings; // user claimable earnings
        uint256 userHarvestJoiningBlock; // user harvest joining block
        uint256 userHarvestUncommittedEarnings; // user harvest uncommitted earnings
        uint256 vaultReserveUncommitted; // vault reserve uncommitted
        CommonTypes.UserPosition position; // user position
    }

    /// @notice track data for a single harvest, used for commit calculations
    struct HarvestData {
        uint256 harvestId; // harvest id
        uint256 farmEarnings; // farm earnings in the harvest
        uint256 vaultLoss; // farm loss applicable for the vault balance
        uint256 uncommittedLossPerc; // farm loss applicable in percentage for the uncommitted earnings
        uint256 claimableLossPerc; // farm loss applicable in percentage  for the claimable rewards
        uint256 activeAssetsThreshold; // active assets threshold for the harvest
        uint256 divertEarningsThreshold; // divert earnings threshold for the harvest
        uint256 vaultActiveAssets; // vault active assets
        uint256 price; // price for the harvest
        uint256 blockNumber; // block number for the harvest
    }

    /// @notice track data for a user's harvest
    struct UserHarvestData {
        uint256 harvestId; // harvest id
        uint256 harvestJoiningBlock; // harvest joining block
        uint256 claimableEarnings; // claimable earnings
        uint256 uncommittedEarnings; // uncommitted earnings (needed for partial commits)
        uint256 vaultReserveUncommitted; // vault reserve uncommitted (needed for partial commits)
    }

    /// @notice harvest storage for multiple harvests, used for commit calculations
    struct HarvestStorage {
        uint256 vaultReserve; // amount allocated to the vault reserve
        uint256 realClaimableEarnings; // total amount of known claimable earnings (users have committed)
        uint256 realUncommittedEarnings; // total amount of uncommitted earnings (prior to type allocation during commit)
        HarvestData[] harvests; // array of all harvests
        uint256 reserveFactor; // percentage of earnings to be allocated to the reserve
        mapping(address => UserHarvestData) userHarvest; // user => userHarvestData - harvest data for users
    }
}
