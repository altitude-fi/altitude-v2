// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ISupplyLossManager {
    event SupplyLossSnapshot(uint256 snapshotId);

    event WithdrawVaultBorrows(uint256 withdrawn, uint256 vaultBorrows);

    event InjectVaultWindfall(uint256 vaultWindfall, uint256 expectedAmountOut, uint256 amountOut, uint256 slippageFee);

    event RepayVaultRemaining(uint256 vaultBorrowsRemaining, uint256 maxBalance);

    function snapshotSupplyLoss() external;
}
