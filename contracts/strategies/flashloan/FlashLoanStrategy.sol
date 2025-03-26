// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../libraries/utils/FlashLoan.sol";
import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/strategy/IFlashLoanCallback.sol";
import "../../interfaces/internal/flashloan/IFlashLoanStrategy.sol";

/**
 * @title FlashLoanStrategy
 * @dev Contract for integrating with flashloans
 * @author Altitude Labs
 **/

abstract contract FlashLoanStrategy is IFlashLoanStrategy {
    /// @dev For optimized gas usage we don't want to use the 0 value
    enum Step {
        Zero,
        Ready,
        Flashloan,
        Migrate
    }

    // Struct to track the migration state
    struct MigrationState {
        Step step;
        FlashLoan.Info info;
    }

    // Migration state
    MigrationState private migrationState;

    constructor() {
        migrationState.step = Step.Ready;
    }

    /// @notice This is the base function for executing Morpho flashloan provider
    /// @param info The parameters for the flashloan
    function flashLoan(FlashLoan.Info calldata info) external override {
        // Ensure the contract processing the flash loan is the one requesting it
        // For migrating a lender that'd be the Vault.
        if (migrationState.step != Step.Ready) {
            revert FLS_MISSTEP();
        }
        if (info.targetContract != msg.sender) {
            revert FLS_WRONG_TARGET();
        }

        // Set the migration state
        migrationState.step = Step.Flashloan;
        migrationState.info = info;

        _processFlashLoan(info);

        // Update the migration state
        migrationState.step = Step.Ready;
    }

    function _onFlashLoanReceive(uint256 amount, uint256 fee, address flashLoanGiver) internal {
        // Ensure we come from flashLoan() with a trustworthy migration Info
        if (migrationState.step != Step.Flashloan) {
            revert FLS_MISSTEP();
        }
        migrationState.step = Step.Migrate;
        FlashLoan.Info memory info = migrationState.info;

        // If info.targetContract is the Vault, then flashLoan() was called by the Vault.
        // We rely on the flashloan provider only for funds and at worst we'll revert with insufficient amount.
        TransferHelper.safeTransfer(info.asset, info.targetContract, amount);
        IFlashLoanCallback(info.targetContract).flashLoanCallback(info.data, fee);

        // Approve the flashloan giver contract allowance to pull the owed amount
        TransferHelper.safeApprove(info.asset, flashLoanGiver, amount + fee);
    }

    function _processFlashLoan(FlashLoan.Info calldata info) internal virtual;
}
