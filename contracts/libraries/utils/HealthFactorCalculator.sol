// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../interfaces/internal/strategy/lending/ILenderStrategy.sol";

/**
 * @title HealthFactorCalculator
 * @dev Calculate borrow parameters based on the deposited and borrowed amount of a user
 * @author Altitude Labs
 **/

library HealthFactorCalculator {
    /// @notice Calculate the current position's factor for a given user
    /// @param liquidationThreshold to calculate with (typically for the vault)
    /// @param totalSuppliedInBase total supplied amount in base token
    /// @param totalBorrowed total borrowed amount in base token
    /// @return User's health factor factor with 18 decimals (like liquidationThreshold)
    function healthFactor(
        uint256 liquidationThreshold,
        uint256 totalSuppliedInBase,
        uint256 totalBorrowed
    ) internal pure returns (uint256) {
        if (totalBorrowed == 0) return type(uint256).max;

        return (totalSuppliedInBase * liquidationThreshold) / totalBorrowed;
    }

    /// @notice Provides information if a user's position is healthy
    /// @param activeLenderStrategy address of the active lending strategy
    /// @param supplyUnderlying address of the underlying token of the supply token
    /// @param borrowUnderlying address of the underlying token of the borrow token
    /// @param liquidationThreshold to calculate with (typically for the vault)
    /// @param supplyAmount amount of supply tokens
    /// @param borrowAmount amount of borrow tokens
    /// @return true if the position is healthy, false if position can be liquidated
    function isPositionHealthy(
        address activeLenderStrategy,
        address supplyUnderlying,
        address borrowUnderlying,
        uint256 liquidationThreshold,
        uint256 supplyAmount,
        uint256 borrowAmount
    ) internal view returns (bool) {
        uint256 totalSuppliedInBase = ILenderStrategy(activeLenderStrategy).convertToBase(
            supplyAmount,
            supplyUnderlying,
            borrowUnderlying
        );

        return healthFactor(liquidationThreshold, totalSuppliedInBase, borrowAmount) >= 1e18; // 1e18 represents 1. In case the health factor is lower than 1, it is unhealthy position
    }

    /// @notice Calculate the amount the user can borrow
    /// @param supplyThreshold to calculate with (typically for the vault)
    /// @param totalSuppliedInBase total supplied amount in base token
    /// @param totalBorrowed total borrowed amount in base token
    /// @return Amount that can be borrowed
    function availableBorrow(
        uint256 supplyThreshold,
        uint256 totalSuppliedInBase,
        uint256 totalBorrowed
    ) internal pure returns (uint256) {
        uint256 borrowedAmountAvailable = (totalSuppliedInBase * supplyThreshold) / 1e18; // 1e18 represents a 100%. supplyThreshold is in percentage
        if (borrowedAmountAvailable < totalBorrowed) {
            return 0;
        }

        return borrowedAmountAvailable - totalBorrowed;
    }

    /// @notice Calculate our desired borrow for a given supply amount
    /// @param activeLenderStrategy address of the active lending strategy
    /// @param supplyUnderlying address of the underlying token of the supply token
    /// @param borrowUnderlying address of the underlying token of the borrow token
    /// @param targetThreshold to calculate with (typically for the vault)
    /// @param supplyAmount amount of supply tokens
    function targetBorrow(
        address activeLenderStrategy,
        address supplyUnderlying,
        address borrowUnderlying,
        uint256 targetThreshold,
        uint256 supplyAmount
    ) internal view returns (uint256) {
        return
            (ILenderStrategy(activeLenderStrategy).convertToBase(supplyAmount, supplyUnderlying, borrowUnderlying) *
                targetThreshold) / 1e18; // 1e18 represents a 100%. targetThreshold is in percentage
    }
}
