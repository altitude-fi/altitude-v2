// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title Chainlink Price Consumer
 * - Features:
 *   # Get latest price for single price feed
 *   # Get latest price for derived price feed
 * @author Altitude Labs
 **/
contract ChainlinkPriceFeed {
    // Chainlink Price Feed Errors
    error CP_FEED_INVALID_DECIMALS();

    /**
     * @notice Get the latest price for Single Price Feed
     * @param priceFeed AggregatorV3Interface Price Feed
     */
    function getLatestPrice(address priceFeed) external view returns (int256 price) {
        (
            ,
            /*uint80 roundID*/
            price,
            /*uint startedAt*/
            /*uint timeStamp*/
            /*uint80 answeredInRound*/
            ,
            ,

        ) = AggregatorV3Interface(priceFeed).latestRoundData();
    }

    /**
     * @notice Getting a different price denomination
     * @param _base Base price feed
     * @param _quote Derived price feed
     * @param _decimals Derived asset decimals
     *
     * Example:
     * _base -> BTC/USD
     * _quote -> USDC/USD
     * _decimals -> USDC's decimals -> 6
     * -> BTC/USDC price
     */
    function getDerivedPrice(address _base, address _quote, uint8 _decimals) public view returns (int256) {
        if (_decimals == uint8(0) || _decimals > uint8(18)) {
            revert CP_FEED_INVALID_DECIMALS();
        }

        int256 decimals = int256(10 ** uint256(_decimals));
        (, int256 basePrice, , , ) = AggregatorV3Interface(_base).latestRoundData();
        uint8 baseDecimals = AggregatorV3Interface(_base).decimals();
        basePrice = _scalePrice(basePrice, baseDecimals, _decimals);

        (, int256 quotePrice, , , ) = AggregatorV3Interface(_quote).latestRoundData();
        uint8 quoteDecimals = AggregatorV3Interface(_quote).decimals();
        quotePrice = _scalePrice(quotePrice, quoteDecimals, _decimals);

        return (basePrice * decimals) / quotePrice;
    }

    function _scalePrice(int256 _price, uint8 _priceDecimals, uint8 _decimals) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10 ** uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10 ** uint256(_priceDecimals - _decimals));
        }
        return _price;
    }
}
