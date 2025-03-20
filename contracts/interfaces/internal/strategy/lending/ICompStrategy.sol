// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ICompStrategy {
    // Strategy Compound Errors
    error SC_DEPOSIT_FAILED();
    error SC_BASE_REPAY_FAILED();
    error SC_BASE_BORROW_FAILED();
    error SC_WITHDRAW_ALL_FAILED();
    error SC_BASE_GET_IN_BASE_WRONG_FROM_ASSET();
    error SC_BASE_COMPTROLLER_ENTER_MARKETS_FAILED();
}
