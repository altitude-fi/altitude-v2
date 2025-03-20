// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title ProxyExtension
 * @dev Abstraction for proxies to call delegatecall
 * @author Altitude Labs
 **/

contract ProxyExtension {
    /// @notice Delegate call helper function
    function _exec(address executable, bytes memory func) internal returns (bytes memory) {
        (bool success, bytes memory data) = executable.delegatecall(func);
        _parseResult(success);

        return data;
    }

    /// @notice Handles delegate call result
    function _parseResult(bool success) internal pure {
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
