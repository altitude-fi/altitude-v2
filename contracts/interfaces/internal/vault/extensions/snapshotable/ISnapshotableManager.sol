// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../harvestable/IHarvestableManager.sol";
import "../supply-loss/ISupplyLossManager.sol";

/**
 * @author Altitude Protocol
 **/

interface ISnapshotableManager is IHarvestableManager, ISupplyLossManager {
    event UserCommit(
        address account,
        uint256 supplyIndex,
        uint256 supplyBalance,
        uint256 borrowIndex,
        uint256 borrowBalance,
        uint256 userHarvestUncommittedEarnings
    );
    event InjectSupply(uint256 actualInjected, uint256 amountToInject);

    function updatePosition(address account) external payable returns (uint256);

    function updatePositionTo(address account, uint256 snapshotId) external returns (uint256);

    function updatePositions(address[] calldata accounts) external returns (uint256);

    function injectSupply(uint256 targetTotalSupply, uint256 atIndex, address funder) external;
}
