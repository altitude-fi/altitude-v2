// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./ISupplyLossManager.sol";
import "../../../../../libraries/types/SupplyLossTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface ISupplyLossVaultV1 is ISupplyLossManager {
    function getSupplyLossSnapshot(uint256 id) external view returns (SupplyLossTypes.SupplyLoss memory);
}
