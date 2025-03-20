// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../VaultCore.sol";
import "../../../interfaces/external/strategy/lending/Aave/IWETH.sol";

/**
 * @title VaultETH
 * @dev Vault that allows users to have as a supply asset ETH and as a borrow assets an ERC20 token
 * @author Altitude Labs
 **/

contract VaultETH is VaultCoreV1 {
    receive() external payable {
        assert(msg.sender == supplyUnderlying);
    }

    /// @notice Convert ETH to WETH to reuse all vault logic
    /// @param amount amount of ETH to deposit
    function _preDeposit(uint256 amount) internal override {
        if (amount != msg.value) {
            revert VC_V1_ETH_INSUFFICIENT_AMOUNT();
        }
        IWETH(supplyUnderlying).deposit{value: amount}();
    }

    /// @notice Convert WETH to ETH and transfer back to the user
    /// @param withdrawAmount amount of WETH to withdraw
    /// @param to address to transfer the ETH to
    function _postWithdraw(uint256 withdrawAmount, address to) internal override returns (uint256) {
        IWETH(supplyUnderlying).withdraw(withdrawAmount);
        TransferHelper.safeTransferNative(to, withdrawAmount);

        return withdrawAmount;
    }
}
