// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "../ILendingProtocolMigration.sol";

interface ICompoundMigration is ILendingProtocolMigration {
    function migrateDeposit(
        address[] calldata lpAssets,
        uint256[] calldata lpAmounts,
        uint256[] calldata underlyingAmounts,
        address vault
    ) external returns (uint256 depositAmount);

    function migrateBorrow(
        MigrationBorrowParams calldata params,
        address[] calldata borrowedAssets,
        address[] calldata borrowedCAssets,
        uint256[] calldata borrowedAmounts
    ) external returns (uint256);
}
