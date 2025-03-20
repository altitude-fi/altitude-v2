// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@chainlink/contracts/src/v0.8/Denominations.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/internal/oracles/IPriceSource.sol";
import "../interfaces/internal/oracles/IChainlinkPrice.sol";
import "../interfaces/external/IWStETH.sol";
import "../interfaces/external/IStETH.sol";

import "../libraries/utils/Utils.sol";

/**
 * @title Chainlink price
 * @notice Get an asset pair price from Chainlink
 * @author Altitude Labs
 **/

contract ChainlinkPrice is IPriceSource, IChainlinkPrice, Ownable {
    /// @notice Feed data older than this will cause a revert
    uint256 public immutable STALE_DATA_SECONDS;

    /// @notice Address for the wstETH token
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    /// @notice Address for the stETH token
    address public immutable STETH_ADDRESS;

    /// @notice Chainlink Feed Registry
    FeedRegistryInterface public immutable FEED_REGISTRY;

    /// @dev Some (WETH, WBTC) addresses must be replaced with Chainlink specific values.
    mapping(address => address) public assetMap;

    /// @notice Derived prices will go through this currency
    address public immutable LINKING_DENOMINATION;

    /// @param feedRegistry Chainlink feed registry address
    /// @param fromAsset array of asset addresses to be replaced
    /// @param toAsset array of asset addresses to replace with
    /// @param derivedLink asset to go through for derived prices
    /// @param staleDataSeconds after this many seconds without updates the feed is considered outdated
    constructor(
        FeedRegistryInterface feedRegistry,
        address[] memory fromAsset,
        address[] memory toAsset,
        address derivedLink,
        uint256 staleDataSeconds
    ) {
        if (fromAsset.length != toAsset.length) {
            revert CL_PRICE_INVALID_ASSET_MAP();
        }

        FEED_REGISTRY = feedRegistry;
        uint256 mapLength = fromAsset.length;
        for (uint256 i; i < mapLength; ) {
            assetMap[fromAsset[i]] = toAsset[i];
            unchecked {
                ++i;
            }
        }

        LINKING_DENOMINATION = derivedLink;
        STALE_DATA_SECONDS = staleDataSeconds;

        STETH_ADDRESS = IWStETH(WSTETH_ADDRESS).stETH();
    }

    /** @notice Price of 1 `fromAsset` in USD, using 8 decimal count
     * @param fromAsset Asset we want the price of
     * @return price The price of `fromAsset` in USD with 8 decimals
     */
    function getInUSD(address fromAsset) external view override returns (uint256) {
        return _getInBase(fromAsset, Denominations.USD, 8);
    }

    /**
     * @notice One `fromAsset` token is worth this many `toAsset` tokens.
     * @param fromAsset Asset we want the price of
     * @param toAsset Asset we want the price in
     * @return price The price of `fromAsset` in `toAsset` with `toAsset` decimals
     */
    function getInBase(address fromAsset, address toAsset) public view override returns (uint256) {
        return _getInBase(fromAsset, toAsset, IERC20Metadata(toAsset).decimals());
    }

    /**
     * @notice One `fromAsset` token is worth this many `toAsset` tokens.
     * @param fromAsset Asset we want the price of
     * @param toAsset Asset we want the price in
     * @param targetDecimals Number of decimals for the returned price
     * @return price The price of `fromAsset` in `toAsset` with `toAsset` decimals
     */
    function _getInBase(
        address fromAsset,
        address toAsset,
        uint8 targetDecimals
    ) internal view returns (uint256 price) {
        // Get the price of the fromAsset in LINKING_DENOMINATION
        (uint256 basePrice, uint8 basePriceDecimals) = _getPrice(_mapAsset(fromAsset));

        toAsset = _mapAsset(toAsset);
        if (toAsset == LINKING_DENOMINATION) {
            // If the target asset is LINKING_DENOMINATION, just scale to the target decimals
            price = Utils.scaleAmount(basePrice, basePriceDecimals, targetDecimals);
        } else {
            // else, get the price of toAsset in LINKING_DENOMINATION
            (uint256 quotePrice, uint8 quotePriceDecimals) = _getPrice(toAsset);

            // and their division will give us the price in toAsset
            price = Utils.scaleAmount(basePrice, basePriceDecimals, targetDecimals + quotePriceDecimals) / quotePrice;
        }

        return price;
    }

    /// @notice Add a new asset pair
    /// @param assetFrom Asset address to be replaced with `assetTo`
    /// @param assetTo Asset address to use instead of `assetFrom`
    function addAssetMap(address assetFrom, address assetTo) external override onlyOwner {
        if (assetMap[assetFrom] != address(0)) {
            revert CL_CAN_NOT_EXISTING_ASSET_MAP();
        }

        assetMap[assetFrom] = assetTo;
        emit AssetMapped(assetFrom, assetTo);
    }

    /// @param requestedAsset Asset we want the price of
    /// @return price The price of `base` in `LINKING_DENOMINATION`
    /// @return decimals Decimals for the returned price
    /// @dev Price of wstETH is the price of stETH, adjusted by the current wrap ratio
    function _getPrice(address requestedAsset) private view returns (uint256 price, uint8 decimals) {
        if (requestedAsset == LINKING_DENOMINATION) {
            return (1, 0);
        }

        address lookup = requestedAsset == WSTETH_ADDRESS ? STETH_ADDRESS : requestedAsset;

        (, int256 answer, , uint256 updatedAt, ) = FEED_REGISTRY.latestRoundData(lookup, LINKING_DENOMINATION);

        if (answer <= 0) {
            revert CL_PRICE_NON_POSITIVE_PRICE();
        }
        if (updatedAt + STALE_DATA_SECONDS <= block.timestamp) {
            revert CL_PRICE_STALE_PRICE_FEED();
        }

        price = uint256(answer);
        decimals = FEED_REGISTRY.decimals(lookup, LINKING_DENOMINATION);

        if (requestedAsset == WSTETH_ADDRESS) {
            price = IStETH(STETH_ADDRESS).getPooledEthByShares(price);
        }
    }

    /// @notice Replace some asset addresses with Chainlink specific values
    /// @param asset Asset address to be replaced
    /// @return mapped Asset address to use instead of `asset`
    function _mapAsset(address asset) private view returns (address) {
        address mapped = assetMap[asset];
        if (mapped != address(0)) {
            return mapped;
        }

        return asset;
    }
}
