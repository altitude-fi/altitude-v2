// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../libraries/utils/HealthFactorCalculator.sol";
import "../../../interfaces/internal/vault/IVaultCore.sol";
import "../../../interfaces/internal/vault/IVaultRegistry.sol";
import "../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";
import "../../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import "../../../interfaces/internal/misc/incentives/rebalance/IRebalanceIncentivesController.sol";

/**
 * @title RebalanceIncentivesController
 * @dev Contract to incentivise addresses that are processing vault rebalancing under certain conditions
 * @dev rewards for stabilizing the protocol
 * @dev note: placeholder contract - incentives are not active yet
 * @author Altitude Labs
 **/

contract RebalanceIncentivesController is Ownable, IRebalanceIncentivesController {
    uint256 public override minDeviation;
    uint256 public override maxDeviation;

    address public immutable override vault;

    /// @notice The token used for rewards payment
    address public immutable rewardToken;

    /**
     * @param rewardToken_ The token being paid out as a reward
     * @param vaultAddress_ The vault the incentives will be provided for
     * @param minDeviation_ The threshold deviation below on to send incentives
     * @param maxDeviation_ The threshold deviation above on to send incentives
     */
    constructor(
        address rewardToken_,
        address vaultAddress_,
        uint256 minDeviation_,
        uint256 maxDeviation_
    ) {
        vault = vaultAddress_;
        _validateDeviations(minDeviation_, maxDeviation_);
        rewardToken = rewardToken_;

        minDeviation = minDeviation_;
        maxDeviation = maxDeviation_;
    }

    /// @notice Set rebalance thresholds
    /// @param minDeviation_ minDeviation_ value
    /// @param maxDeviation_ maxDeviation_ value
    function setThresholds(uint256 minDeviation_, uint256 maxDeviation_) external override onlyOwner {
        _validateDeviations(minDeviation_, maxDeviation_);

        minDeviation = minDeviation_;
        maxDeviation = maxDeviation_;

        emit UpdateRebalanceThresholds(minDeviation_, maxDeviation_);
    }

    function rebalance() external override {
        if (!canRebalance()) {
            revert RIC_CAN_NOT_REBALANCE();
        }

        IVaultCoreV1(vault).rebalance();
    }

    /// @return The current LTV ratio of the vault, 18 decimals
    function currentThreshold() public view override returns (uint256) {
        ILenderStrategy activeLenderStrategy = ILenderStrategy(IVaultCoreV1(vault).activeLenderStrategy());

        uint256 supplyInBase = activeLenderStrategy.convertToBase(
            activeLenderStrategy.supplyBalance(),
            activeLenderStrategy.supplyAsset(),
            activeLenderStrategy.borrowAsset()
        );

        uint256 totalBorrowed = activeLenderStrategy.borrowBalance();

        return (totalBorrowed * 1e18) / supplyInBase;
    }

    /// @notice check if the msg.sender will be incentivised for processing the rebalance
    /// @return true if the msg.sender will be incentivised for processing the rebalance
    /// @dev note: placeholder function - incentives are not active yet
    function canRebalance() public view override returns (bool) {
        uint256 threshold = currentThreshold();
        address activeFarmStrategy = IVaultCoreV1(vault).activeFarmStrategy();

        uint256 targetThreshold = IVaultCoreV1(vault).targetThreshold();
        uint256 minThreshold = targetThreshold - (targetThreshold * minDeviation) / 1e18;
        uint256 maxThreshold = targetThreshold + (targetThreshold * maxDeviation) / 1e18;

        if (threshold < minThreshold) {
            return true;
        }
        if (threshold > maxThreshold) {
            if (
                IFarmDispatcher(activeFarmStrategy).balance() > 0 &&
                IVaultCoreV1(vault).debtToken().balanceOf(address(vault)) > 0
            ) {
                return true;
            }
        }
        return false;
    }

    /// @notice validate the provided deviations
    /// @param minDeviation_ minDeviation_ value
    /// @param maxDeviation_ maxDeviation_ value
    function _validateDeviations(uint256 minDeviation_, uint256 maxDeviation_) internal pure {
        // Check that the maxDeviation is not too high
        if (maxDeviation_ > 1e18) {
            // 1e18 represents a 100%. maxDeviation_ is in percentage
            revert RIC_INVALID_DEVIATIONS();
        }

        // Check that the minDeviation is not too high
        if (minDeviation_ > 1e18) {
            // 1e18 represents a 100%. minDeviation_ is in percentage
            revert RIC_INVALID_DEVIATIONS();
        }
    }
}
