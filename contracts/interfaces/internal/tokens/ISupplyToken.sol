// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IDebtToken.sol";
import "./IInterestToken.sol";

/**
 * @author Altitude Protocol
 **/

interface ISupplyToken is IInterestToken {
    // Supply token Errors
    error ST_NOT_ENOUGH_BALANCE();
    error ST_NOT_ENOUGH_ALLOWANCE();

    function transferMax(address to) external returns (bool);

    function transferFromMax(address from, address to) external returns (bool);
}
