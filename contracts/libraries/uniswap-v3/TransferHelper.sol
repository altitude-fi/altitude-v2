// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Transfer Helper Library
 * @dev Contains helper methods for interacting with ERC20 tokens that do not consistently return true/false
 * @author Uniswap
 **/
library TransferHelper {
    // Tranfer helper library Errors
    error TH_SAFE_TRANSFER_FAILED();
    error TH_SAFE_TRANSFER_FROM_FAILED();
    error TH_SAFE_TRANSFER_NATIVE_FAILED();
    error TH_SAFE_APPROVE();
    error TH_SAFE_APPROVE_RESET();

    function safeTransfer(address token, address to, uint256 value) internal {
        bool toThrow = _call(token, abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        if (toThrow) {
            revert TH_SAFE_TRANSFER_FAILED();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        bool toThrow = _call(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        if (toThrow) {
            revert TH_SAFE_TRANSFER_FROM_FAILED();
        }
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(address token, address to, uint256 value) internal {
        // Reset approval first
        bool toThrow = _call(token, abi.encodeWithSelector(IERC20.approve.selector, to, 0));
        if (toThrow) {
            revert TH_SAFE_APPROVE_RESET();
        }

        toThrow = _call(token, abi.encodeWithSelector(IERC20.approve.selector, to, value));
        if (toThrow) {
            revert TH_SAFE_APPROVE();
        }
    }

    function _call(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory resultData) = token.call(data);
        if (!success || (resultData.length > 0 && !abi.decode(resultData, (bool)))) {
            return true;
        }

        return false;
    }

    function safeTransferNative(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) {
            revert TH_SAFE_TRANSFER_NATIVE_FAILED();
        }
    }
}
