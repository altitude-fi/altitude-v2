// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

import {IToken} from "../interfaces/IToken.sol";
import {TokensGenerator} from "../utils/TokensGenerator.sol";

import "../../contracts/strategies/swap/SwapStrategy.sol";
import "../../contracts/interfaces/internal/oracles/IPriceSource.sol";

// Mint in 1:1 ratio for every token and amount
contract BaseSwapStrategy is SwapStrategy, Test, TokensGenerator {
    using stdStorage for StdStorage;

    uint256 public swapInFee;

    constructor(address oracle) SwapStrategy(address(0), IPriceSource(oracle)) {}

    function setSwapInFee(uint256 feePerc) public {
        swapInFee = feePerc;
    }

    function swapInBase(
        address assetFrom,
        address assetTo,
        uint256 amount
    ) external override returns (uint256 amountOut) {
        IToken(assetFrom).transferFrom(msg.sender, address(this), amount);

        uint256 fromDecimals = IToken(assetFrom).decimals();
        uint256 price = priceSource.getInBase(assetFrom, assetTo);
        amountOut = (amount * price) / 10**fromDecimals;

        amountOut -= (amountOut * swapInFee) / 100;

        mintToken(assetTo, msg.sender, amountOut);
    }

    function swapOutBase(
        address assetFrom,
        address assetTo,
        uint256 amountOut,
        uint256 amountInMaximum
    ) external override returns (uint256 amountIn) {
        IToken(assetFrom).transferFrom(msg.sender, address(this), amountInMaximum);
        amountIn = amountInMaximum;

        mintToken(assetTo, msg.sender, amountOut);
    }

    function _routeSlippage(address, address) internal pure override returns (uint256 slippage) {
        slippage = 0;
    }

    function getAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        uint256 fromDecimals = IToken(assetFrom).decimals();
        uint256 toDecimals = IToken(assetTo).decimals();

        if (amountOut == type(uint256).max) {
            amountIn = type(uint256).max;
        } else {
            amountIn = (amountOut * 10**fromDecimals) / 10**toDecimals;
        }
    }

    function getAmountOut(
        address assetFrom,
        address assetTo,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        uint256 fromDecimals = IToken(assetFrom).decimals();
        uint256 toDecimals = IToken(assetTo).decimals();
        amountOut = ((amountIn * 10**toDecimals) / 10**fromDecimals);
    }
}
