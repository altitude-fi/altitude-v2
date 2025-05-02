// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ISkimStrategy {
    /** @notice Emitted when an asset is not allowed for skim */
    error SK_NON_SKIM_ASSET();
    /** @notice Emitted when the receiver address is invalid */
    error SK_INVALID_RECEIVER();

    function nonSkimAssets(address asset) external view returns (bool);

    function skim(address[] calldata assets, address receiver) external;
}
