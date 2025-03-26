// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./ILiquidatableManager.sol";
import "../../../../../libraries/types/VaultTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface ILiquidatableVaultV1 is ILiquidatableManager {
    function isUserForLiquidation(address userAddress) external view returns (bool isUserForLiquidator);

    function setLiquidationConfig(VaultTypes.LiquidatableConfig memory liqConfig) external;

    function getLiquidationConfig() external view returns (address, uint256, uint256, uint256, uint256);
}
