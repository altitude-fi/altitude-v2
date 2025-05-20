// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../swap/ISwapStrategyConfiguration.sol";

/**
 * @author Altitude Protocol
 **/

interface IFarmStrategy is ISwapStrategyConfiguration {
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event RewardsRecognition(uint256 rewards);
    event EmergencyWithdraw();
    event EmergencySwap();
    event SetRewardAssets(address[] oldAssets, address[] newAssets);

    error FS_ONLY_DISPATCHER();
    error FS_IN_EMERGENCY_MODE();
    error FM_NOT_IN_EMERGENCY_MODE();

    function rewardAssets(uint256) external returns (address);

    function inEmergency() external view returns (bool);

    function asset() external view returns (address);

    function farmAsset() external view returns (address);

    function farmDispatcher() external view returns (address);

    function rewardsRecipient() external view returns (address);

    function deposit(uint256 amount) external;

    function recogniseRewardsInBase() external returns (uint256 rewards);

    function withdraw(uint256 amount) external returns (uint256 amountWithdrawn);

    function emergencyWithdraw() external;

    function emergencySwap(address[] calldata tokens) external returns (uint256 amountWithdrawn);

    function balance() external view returns (uint256);

    function balanceAvailable() external view returns (uint256);

    function setRewardAssets(address[] memory rewardAssets_) external;
}
