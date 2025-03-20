// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IFlashLoanCallback {
    function flashLoanCallback(bytes calldata, uint256) external;
}
