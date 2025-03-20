// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "../ILendingProtocolMigration.sol";

interface IAaveMigration is ILendingProtocolMigration {
    function migrateDeposit(
        address[] calldata lpAssets,
        uint256[] calldata lpUnderlyingAmounts,
        address vault
    ) external returns (uint256 depositAmount);

    function migrateBorrow(
        MigrationBorrowParams calldata params,
        address[] calldata borrowedAssets,
        uint256[] calldata borrowedAmounts,
        uint256[] calldata borrowedRateModes
    ) external returns (uint256 borrowAmount);

    function aEthToken() external view returns (address);
}
