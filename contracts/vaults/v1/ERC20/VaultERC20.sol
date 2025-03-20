// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../VaultCore.sol";

/**
 * @title VaultERC20
 * @dev Vault that allows users to have as a supply and borrow assets ERC20 tokens
 * @author Altitude Labs
 **/

contract VaultERC20 is VaultCoreV1 {
    /// @notice Transfer supply asset from the user to the vault
    /// @param amount amount of supply asset to deposit
    function _preDeposit(uint256 amount) internal override {
        TransferHelper.safeTransferFrom(supplyUnderlying, msg.sender, address(this), amount);
    }

    /// @notice Transfer supply token from the vault to the user
    /// @param withdrawAmount amount of supply token to withdraw
    /// @param to address to transfer the supply token to
    function _postWithdraw(uint256 withdrawAmount, address to) internal override returns (uint256) {
        TransferHelper.safeTransfer(supplyUnderlying, to, withdrawAmount);
        return withdrawAmount;
    }
}
