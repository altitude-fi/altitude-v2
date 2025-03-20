// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IPriceSource {
    /// @return Price of 1 `fromAsset` in `toAsset`, using toAsset's decimal count
    function getInBase(address fromAsset, address toAsset) external view returns (uint256);

    /// @return Price of 1 `fromAsset` in USD, using 8 decimal count
    function getInUSD(address fromAsset) external view returns (uint256);
}
