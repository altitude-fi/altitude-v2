// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../interfaces/internal/strategy/swap/ISwapStrategy.sol";

/* @title SwapStrategy
 * @dev Base contract for DEX integration
 * @dev implements generic functions for DEX integration
 * @author Altitude Labs
 **/

abstract contract SwapStrategy is ISwapStrategy, Ownable {
    uint256 public constant SLIPPAGE_BASE = 1_000_000;

    /** @notice UniswapV3 swaps address */
    address public immutable override swapRouter;

    /** @notice A Price Source address */
    IPriceSource public override priceSource;

    /** @notice Emitted when new Multihop route is set */
    event SwapPairSet(address assetFrom, address assetTo, uint256 slippage);

    /** @notice Emitted when new Maximum Slippage is updated */
    event SwapProceed(uint256 amountOut);

    constructor(address _swapRouter, IPriceSource _priceSource) Ownable() {
        priceSource = _priceSource;
        swapRouter = _swapRouter;
    }

    function setPriceSource(address newPriceSource) external override onlyOwner {
        priceSource = IPriceSource(newPriceSource);
        emit PriceSourceUpdated(newPriceSource);
    }

    /**
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @return slippage Swap strategy's slippage for this route
     */
    function _routeSlippage(address assetFrom, address assetTo) internal view virtual returns (uint256 slippage);

    /**
     * @notice Calculate the minimum expected amount from the swap
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param baseAmount Swap amount of inbound asset
     */
    function getMinimumAmountOut(
        address assetFrom,
        address assetTo,
        uint256 baseAmount,
        uint256 slippage
    ) public view virtual override returns (uint256) {
        uint256 price = _getPrice(assetFrom, assetTo);

        uint256 initialQuoteAmount = (baseAmount * price) / 10 ** IERC20Metadata(assetFrom).decimals();

        return _applySlippage(initialQuoteAmount, slippage);
    }

    function _applySlippage(uint256 initialQuoteAmount, uint256 slippage) internal pure returns (uint256 quoteAmount) {
        quoteAmount = initialQuoteAmount;
        if (slippage > 0 && quoteAmount > 0) {
            // apply slippage
            quoteAmount -= (quoteAmount * slippage) / SLIPPAGE_BASE;

            if (quoteAmount == initialQuoteAmount) {
                /// @dev If the amounts were so small that slippage didn't have an effect due to rounding
                quoteAmount -= 1;
            }
        }
    }

    function _getPrice(address assetFrom, address assetTo) internal view returns (uint256) {
        try priceSource.getInBase(assetFrom, assetTo) returns (uint256 price) {
            return price;
        } catch {
            revert SWAP_STRATEGY_PRICE_SOURCE_GET_IN_BASE();
        }
    }

    /**
     * @notice Calculate the minimum expected amount from the swap
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param baseAmount Swap amount of inbound asset
     */
    function getMinimumAmountOut(
        address assetFrom,
        address assetTo,
        uint256 baseAmount
    ) external view override returns (uint256) {
        return getMinimumAmountOut(assetFrom, assetTo, baseAmount, _routeSlippage(assetFrom, assetTo));
    }

    /**
     * @notice Calculate the maximum amount in that needs to be provided to get `amountOut`
     * @dev Uses pre-set swap path & slippage.
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amountOut Desired output amount
     */
    function getMaximumAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut,
        uint256 slippage
    ) public view override returns (uint256) {
        uint256 price = _getPrice(assetFrom, assetTo);

        uint256 initialQuoteAmount = (amountOut * 10 ** IERC20Metadata(assetFrom).decimals()) / price;

        uint256 quoteAmount = initialQuoteAmount + ((initialQuoteAmount * slippage) / SLIPPAGE_BASE);

        if (quoteAmount == initialQuoteAmount && slippage != 0) {
            /// @dev If the amounts were so small that slippage didn't have an effect due to rounding
            quoteAmount += 1;
        }

        return quoteAmount;
    }

    /**
     * @notice Calculate the maximum amount in that needs to be provided to get `amountOut`
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amountOut Desired output amount
     */
    function getMaximumAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut
    ) public view override returns (uint256) {
        return getMaximumAmountIn(assetFrom, assetTo, amountOut, _routeSlippage(assetFrom, assetTo));
    }
}
