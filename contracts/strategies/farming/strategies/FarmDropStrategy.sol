// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./FarmStrategy.sol";
import "../../../interfaces/internal/strategy/farming/IFarmDropStrategy.sol";

/**
 * @title FarmDropStrategy Contract
 * @dev Provides tools to monitor drops in the farm balance value
 * @author Altitude Labs
 **/

abstract contract FarmDropStrategy is Ownable, FarmStrategy, IFarmDropStrategy {
    uint256 public override expectedBalance;
    uint256 public override dropPercentage;
    uint256 public constant override DROP_UNITS = 1e18;

    /// @notice Default drop threshold to revert deposit/withdraw calls is 5%
    uint256 public override dropThreshold = (DROP_UNITS * 5) / 100;

    constructor(
        address farmAssetAddress,
        address farmDispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        address swapStrategyAddress
    ) FarmStrategy(farmAssetAddress, farmDispatcherAddress, rewardsAddress, rewardAssets_, swapStrategyAddress) {}

    /// @notice Set the threshold for reverting deposit/withdraw
    /// @param dropThreshold_ The new threshold in percentage (of DROP_UNITS, 1e18)
    function setDropThreshold(uint256 dropThreshold_) external onlyOwner {
        if (dropThreshold_ > DROP_UNITS) {
            revert FDS_OUT_OF_BOUNDS();
        }

        dropThreshold = dropThreshold_;
    }

    /// @notice Deal with a farm drop during deposit
    /// If a farm drop is detected, the deposit will be reverted
    /// @param amount The amount to deposit
    function deposit(uint256 amount) public override(FarmStrategy, IFarmStrategy) {
        uint256 currentBalance = balance();
        _updateDropPercentage(currentBalance, 0);
        if (dropPercentage > dropThreshold) {
            revert FDS_DROP_EXCEEDED(dropPercentage, dropThreshold);
        }

        // deposit and check for any deposit fees
        expectedBalance = currentBalance;
        super.deposit(amount);
        currentBalance = balance();
        _updateDropPercentage(currentBalance, amount);
        expectedBalance = currentBalance;
    }

    /// @notice Track and handle any possible farm drop on withdraw
    /// If a farm drop is detected, the withdraw will be reverted
    /// @param amountRequested The amount to withdraw

    function withdraw(
        uint256 amountRequested
    ) public override(FarmStrategy, IFarmStrategy) returns (uint256 amountWithdrawn) {
        _updateDropPercentage(balance(), 0);
        if (dropPercentage > dropThreshold) {
            revert FDS_DROP_EXCEEDED(dropPercentage, dropThreshold);
        }
        amountWithdrawn = super.withdraw(amountRequested);
        expectedBalance = balance();
    }

    /// @notice Update the drop percentage on emergencyWithdraw
    function emergencyWithdraw() public override(FarmStrategy, IFarmStrategy) {
        _updateDropPercentage(balance(), 0);
        super.emergencyWithdraw();
        expectedBalance = balance();
    }

    /// @notice Update the drop percentage on emergencySwap
    /// @param assets The assets to swap
    function emergencySwap(
        address[] calldata assets
    ) public override(FarmStrategy, IFarmStrategy) returns (uint256 amountWithdrawn) {
        _updateDropPercentage(balance(), 0);
        amountWithdrawn = super.emergencySwap(assets);
        expectedBalance = balance();
    }

    /// @notice Account for increase/decrease in the farm drop percentage
    /// @param amount Expected balance increase
    function _updateDropPercentage(uint256 currentBalance, uint256 amount) internal {
        dropPercentage = _calculateDropPercentage(currentBalance, expectedBalance + amount, dropPercentage);
    }

    /// @notice Calculates the current drop in farm value as percentage
    /// @return percentage The total drop in farm value as a percentage
    function currentDropPercentage() public view override returns (uint256) {
        return _calculateDropPercentage(balance(), expectedBalance, dropPercentage);
    }

    /// @notice Decrease drop percentage with the rewards that are used to restore it
    function _recogniseRewardsInBase() internal virtual override {
        /// @dev It is assumed the balance to be bigger than the expected one
        // as the rewards have been recognised from the inherited contract
        // The drop percentage is to be decreased with the new rewards
        _updateDropPercentage(balance(), 0);
    }

    /// @notice Track and handle any possible farm drop on recogniseRewardsInBase
    /// @return rewards The amount of rewards recognised
    function recogniseRewardsInBase() public virtual override(FarmStrategy, IFarmStrategy) returns (uint256 rewards) {
        rewards = super.recogniseRewardsInBase();
        expectedBalance = balance();
    }

    /// @notice Calculates the drop in farm value as percentage
    /// @param currentBalance_ The current amount in farming
    /// @param expectedBalance_ The expected amount in farming
    /// @param accumulatedDrop_ The drop percentage accumulated so far
    /// @return amount The total drop in farm value as a percentage
    function _calculateDropPercentage(
        uint256 currentBalance_,
        uint256 expectedBalance_,
        uint256 accumulatedDrop_
    ) private pure returns (uint256) {
        if (expectedBalance_ == 0) {
            // If we expect the farm to be empty there can be no drop
            return 0;
        }

        if (currentBalance_ > expectedBalance_) {
            // Gained value
            uint256 percentage = ((currentBalance_ - expectedBalance_) * DROP_UNITS) / expectedBalance_;
            uint256 percentageAdjustment = (accumulatedDrop_ + ((accumulatedDrop_ * percentage) / DROP_UNITS));
            if (percentageAdjustment > percentage) {
                accumulatedDrop_ = percentageAdjustment - percentage;
            } else {
                // Farm is at net gain, new peak from where we will start tracking losses
                accumulatedDrop_ = 0;
            }
        } else {
            if (currentBalance_ == 0) {
                // Lost everything shortcut
                accumulatedDrop_ = DROP_UNITS;
            } else {
                // Lost some
                uint256 percentage = ((expectedBalance_ - currentBalance_) * DROP_UNITS) / expectedBalance_;
                accumulatedDrop_ = (accumulatedDrop_ - ((accumulatedDrop_ * percentage) / DROP_UNITS)) + percentage;
            }
        }

        return accumulatedDrop_;
    }

    /// @notice Reset drop percentage
    function reset() external override onlyOwner {
        dropPercentage = 0;
        expectedBalance = balance();

        emit ResetDropPercentage();
    }
}
