// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title Utils
 * @notice Helpers
 * @author Altitude Labs
 **/

library Utils {
    /// @notice Accumulated interest for a balance for a given index period
    /// @param balance The current balance of an account
    /// @param fromIndex The index of last balance accumulation
    /// @param toIndex The index the balance to be accumulated to
    /// @return balanceAtIndex The new balance including the accumulation
    function calcBalanceAtIndex(
        uint256 balance,
        uint256 fromIndex,
        uint256 toIndex
    ) internal pure returns (uint256 balanceAtIndex) {
        if (balance == 0) {
            return 0;
        }

        balanceAtIndex = balance;
        if (fromIndex > 0) {
            balanceAtIndex = divRoundingUp(balance * toIndex, fromIndex);
        }
    }

    /// @notice Divide two numbers and round up with 1 wei
    /// @param numerator number
    /// @param denominator denominator
    /// @return result
    function divRoundingUp(uint256 numerator, uint256 denominator) internal pure returns (uint256 result) {
        if (numerator > 0 && denominator > 0) {
            result = numerator / denominator;
            if (result > 0) {
                if (result * denominator < numerator) {
                    result += 1;
                }
            }
        }
    }

    /// @notice Scale a given amount into desired decimals
    /// @param amount_ Amount to scale
    /// @param amountDecimals_ Current scale of the amount
    /// @return targetDecimals_ Desired decimals to scale to
    function scaleAmount(
        uint256 amount_,
        uint8 amountDecimals_,
        uint8 targetDecimals_
    ) internal pure returns (uint256) {
        if (amountDecimals_ < targetDecimals_) {
            return amount_ * (10**(targetDecimals_ - amountDecimals_));
        } else if (amountDecimals_ > targetDecimals_) {
            return amount_ / 10**((amountDecimals_ - targetDecimals_));
        }
        return amount_;
    }

    /// @notice Returns the subtraction of two unsigned integers or zero on underflow.
    function subOrZero(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            if (b > a) return 0;
            return a - b;
        }
    }
}
