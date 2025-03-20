// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title FlashLoan
 * @dev Data types for preparing a flashloan
 * @author Altitude Labs
 **/

library FlashLoan {
    /// @dev Struct of params to be passed between functions executing flashloan logic
    /// @param asset: Address of asset to be borrowed with flashloan
    /// @param amount: Amount of asset to be borrowed with flashloan
    /// @param initiator: Vault's address on which the flashloan logic to be executed
    /// @param data: Contains the encoded params for the flashloan logic
    struct Info {
        address targetContract;
        address asset;
        uint256 amount;
        bytes data;
    }
}
