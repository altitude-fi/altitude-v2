// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "../Aave/IBaseLendingPool.sol";
import "../../../strategy/lending/Aave/IFlashLoanReceiver.sol";
import "../../../../internal/strategy/swap/ISwapStrategy.sol";

interface ILendingProtocolMigration is IFlashLoanReceiver {
    // Lending Protocol Migration Errors
    error MIG_RECEIVE();
    error MIG_FALLBACK();
    error MIG_LP_WITHDRAW_AMOUNT_MISMATCH();
    error MIG_BORROW_MISSTEP();

    /// @dev For optimized gas usage we don't want to use the 0 value
    enum Step {
        Zero,
        Ready,
        Flashloan,
        Migrate
    }

    struct MigrationBorrowParams {
        /** @notice The address of the vault, where everything will be migrated. */
        address vault;
        /** @notice An array of the lending pool collateral assets for the external Lending Protocol. */
        address[] lpAssets;
        /** @notice The collateral amounts, used to be exchanged for underlying collateral amounts from the external Lending Protocol.
        Passed as not always collateral and underlying asset amounts have 1:1 ratio. */
        uint256[] lpAmounts;
        /** @notice The required underlying collateral amounts, which will be withdrawn from the Lending Protocol and migrated to the Altitude vault. */
        uint256[] lpUnderlyingAmounts;
        /** @notice The amount, which will be borrowed from the Altitude vault. */
        uint256 borrowAmount;
        /** @notice Required from the Altitude vault's `borrowOnBehalf` functionality.  */
        uint256 deadline;
        /** The address of the entity, whose assets will be migrated from the external Lending Protocol to the Altitude Vault. */
        address originalInitiator;
        /** @notice Required for the Altitude vault's borrowOnBehalf functionality. Must be signed by `originalInitiator`. See {@BorrowVerifier} for signature parameters. */
        bytes signature;
    }

    event MigrateDeposit(
        address indexed migrator,
        address indexed lpAsset,
        uint256 lpUnderlyingAmount,
        uint256 depositAmount,
        address indexed vault
    );

    event MigrateBorrow(
        address indexed migrator,
        address indexed vault,
        uint256 borrowAmount,
        address[] assets,
        uint256[] amounts
    );

    function WETH() external view returns (address);

    function flashloanPool() external view returns (IBaseLendingPool);

    function swapStrategy() external view returns (ISwapStrategy);
}
