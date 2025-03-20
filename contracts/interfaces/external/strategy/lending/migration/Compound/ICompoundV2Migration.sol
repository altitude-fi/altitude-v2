// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "./ICompoundMigration.sol";

interface ICompoundV2Migration is ICompoundMigration {
    // Compound V2 Migration Errors
    error COMP_V2_MIG_REDEEM();
    error COMP_V2_MIG_REPAY_BORROW_BEHALF();

    function receiveETHAddress() external view returns (address);
}
