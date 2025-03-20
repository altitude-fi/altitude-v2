// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ISkimStrategy {
    /** @notice Emitted when an asset is not allowed for skim */
    error SK_NON_SKIM_ASSET();

    function nonSkimAssets(address asset) external view returns (bool);

    function skim(address[] calldata assets, address receiver) external;
}
