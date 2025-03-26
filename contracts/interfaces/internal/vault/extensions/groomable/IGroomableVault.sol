// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../../../../../libraries/types/VaultTypes.sol";
import "./IGroomableManager.sol";

/**
 * @author Altitude Protocol
 **/

interface IGroomableVaultV1 is IGroomableManager {
    // Groomable Vault Errors
    error GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE();

    function migrateLender(address newStrategy) external;

    function migrateFarmDispatcher(address newFarmDispatcher) external;

    function rebalance() external;

    function setGroomableConfig(VaultTypes.GroomableConfig memory) external;

    function getGroomableConfig() external view returns (address, address, uint256);
}
