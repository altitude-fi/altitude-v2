// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IInterestToken.sol";

/**
 * @author Altitude Protocol
 **/

interface IDebtToken is IInterestToken {
    // Debt token Errors
    error DT_APPROVAL_NOT_SUPPORTED();
    error DT_TRANSFER_NOT_SUPPORTED();
    error DT_ALLOWANCE_INCREASE_NOT_SUPPORTED();
    error DT_ALLOWANCE_DECREASE_NOT_SUPPORTED();

    function balanceOfDetails(address account) external view returns (uint256, uint256, uint256);
}
