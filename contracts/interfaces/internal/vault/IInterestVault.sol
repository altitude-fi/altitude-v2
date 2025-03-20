// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./IVaultStorage.sol";

/**
 * @author Altitude Protocol
 **/

interface IInterestVault is IVaultStorage {
    error IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED();
}
