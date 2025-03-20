// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IMorphoStrategy {
    /** @notice Emitted when there is an assets mismatch on construction */
    error SM_INVALID_MARKET();

    /** @notice Emitted when reward assets are updated */
    event SetRewardAssets(address[] oldAssets, address[] newAssets);

    function setRewardAssets(address[] memory rewardAssets_) external;
}
