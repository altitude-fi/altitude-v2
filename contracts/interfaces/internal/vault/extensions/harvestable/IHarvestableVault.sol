// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IHarvestableManager.sol";
import "../../../../../libraries/types/HarvestTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface IHarvestableVaultV1 is IHarvestableManager {
    function claimableRewards(address account) external view returns (uint256);

    function reserveAmount() external view returns (uint256);

    function getHarvest(uint256 id) external view returns (HarvestTypes.HarvestData memory);

    function getHarvestsCount() external view returns (uint256);

    function getUserHarvest(address user) external view returns (HarvestTypes.UserHarvestData memory);

    function getHarvestData()
        external
        view
        returns (uint256 realClaimableEarnings, uint256 realUncommittedEarnings, uint256 vaultReserve);
}
