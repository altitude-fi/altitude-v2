// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Labs
 **/

interface IRebalanceIncentivesController {
    event UpdateRebalanceDeviation(uint256 minDeviation_, uint256 maxDeviation_);
    event UpdateForceRebalance(bool forceRebalance_);

    // Rebalance Incentives Controller Errors
    error RIC_CAN_NOT_REBALANCE();
    error RIC_INVALID_DEVIATIONS();

    function vault() external view returns (address);

    function minDeviation() external view returns (uint256);

    function maxDeviation() external view returns (uint256);

    function rewardToken() external view returns (address);

    function forceRebalance() external view returns (bool);

    function currentThreshold() external view returns (uint256);

    function canRebalance() external view returns (bool);

    function setDeviation(uint256 minDeviation_, uint256 maxDeviation_) external;

    function setForceRebalance(bool forceRebalance_) external;

    function rebalance() external;
}
