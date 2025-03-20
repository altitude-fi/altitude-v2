// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../../../libraries/utils/FlashLoan.sol";

/**
 * @author Altitude Labs
 **/

interface IFlashLoanStrategy {
    // FlashLoan Errors
    error FLS_MISSTEP();
    error FLS_WRONG_TARGET();

    function flashLoan(FlashLoan.Info calldata info) external;
}
