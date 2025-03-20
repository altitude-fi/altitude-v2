// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IChainlinkPrice {
    event AssetMapped(address assetFrom, address assetTo);

    // Chainlink Price Errors
    error CL_PRICE_STALE_PRICE_FEED();
    error CL_PRICE_INVALID_ASSET_MAP();
    error CL_PRICE_NON_POSITIVE_PRICE();
    error CL_CAN_NOT_EXISTING_ASSET_MAP();

    function addAssetMap(address assetFrom, address assetTo) external;
}
