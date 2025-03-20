// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title CommonTypes
 * @dev Input parameters for not having "Stack too deep"
 * @author Altitude Labs
 **/

library CommonTypes {
    /// @notice struct for the supply and borrow position of a user
    struct UserPosition {
        uint256 supplyIndex; // supplyIndex for the user
        uint256 supplyBalance; // supplyBalance for the user
        uint256 borrowIndex; // borrowIndex for the user
        uint256 borrowBalance; // borrowBalance for the user
    }

    /// @notice defines the different types of snapshots
    enum SnapshotClass {
        Harvest,
        SupplyLoss
    }

    /// @notice struct for different commit types
    struct SnapshotType {
        uint256 id; // id of the snapshot
        uint256 kind; // kind of the snapshot, where 0 is harvest, 1 is supply loss
        uint256 supplyIndex; // supplyIndex for the snapshot
        uint256 borrowIndex; // borrowIndex for the snapshot
    }
}
