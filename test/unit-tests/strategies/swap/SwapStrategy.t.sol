// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {BaseGetter} from "../../../base/BaseGetter.sol";
import {BaseSwapStrategy} from "../../../base/BaseSwapStrategy.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";

import {IPriceSource} from "../../../../contracts/interfaces/internal/oracles/IPriceSource.sol";
import {ISwapStrategy} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";

contract SwapStrategyTest is TokensGenerator {
    IPriceSource public priceSource;
    ISwapStrategy public swapStrategy;

    uint256 public constant SLIPPAGE = 100000; // 10%

    function setUp() public {
        priceSource = IPriceSource(BaseGetter.getBasePriceSource());
        swapStrategy = new BaseSwapStrategy(address(priceSource));
    }

    function test_ConstructedCorrectly() public view {
        assertEq(address(swapStrategy.priceSource()), address(priceSource));
        assertEq(swapStrategy.swapRouter(), address(0));
    }

    function test_SetPriceSource() public {
        address newPriceSource = vm.randomAddress();
        swapStrategy.setPriceSource(newPriceSource);
        assertEq(address(swapStrategy.priceSource()), newPriceSource);
    }

    function test_SetPriceSourceUnauthorized() public {
        address newPriceSource = vm.randomAddress();

        vm.prank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        swapStrategy.setPriceSource(newPriceSource);
    }

    function test_getMinimumAmountOut() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);
        uint256 amountOut = swapStrategy.getMinimumAmountOut(tokenA, tokenB, 1e6, SLIPPAGE);

        // Price is 1:1 with different decimals
        assertEq(amountOut, 9e17); // 90% of (1e6 * price)
    }

    function test_getMinimumAmountOutZeroSlippage() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);
        uint256 amountOut = swapStrategy.getMinimumAmountOut(tokenA, tokenB, 1e6, 0);

        assertEq(amountOut, 1e18);
    }

    function test_getMinimumAmountOutZeroQuoteAmount() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);
        uint256 amountOut = swapStrategy.getMinimumAmountOut(tokenA, tokenB, 0, SLIPPAGE);

        assertEq(amountOut, 0);
    }

    function test_getMinimumAmountOutNoSlippageEffect() public {
        address tokenA = BaseGetter.getBaseERC20(18);
        address tokenB = BaseGetter.getBaseERC20(6);
        uint256 amountOut = swapStrategy.getMinimumAmountOut(
            tokenA,
            tokenB,
            1e17,
            1 // 1 wei so the slippage doesn't have an effect
        );

        assertEq(amountOut, 99999);
    }

    function test_getMinimumAmountOutOracleReverts() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);

        vm.mockCallRevert(address(priceSource), abi.encodeWithSelector(IPriceSource.getInBase.selector), "revert");
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_PRICE_SOURCE_GET_IN_BASE.selector);
        swapStrategy.getMinimumAmountOut(tokenA, tokenB, 1e6, SLIPPAGE);
    }

    function test_getMaximumAmountIn() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);

        uint256 amountIn = swapStrategy.getMaximumAmountIn(tokenA, tokenB, 1e18, SLIPPAGE);

        // Price is 1:1 with different decimals
        assertEq(amountIn, 11e5);
    }

    function test_getMaximumAmountInZeroSlippage() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);

        uint256 amountIn = swapStrategy.getMaximumAmountIn(tokenA, tokenB, 1e18, 0);
        assertEq(amountIn, 1000000);
    }

    function test_getMinimumAmountInNoSlippageEffect() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);

        uint256 amountIn = swapStrategy.getMaximumAmountIn(tokenA, tokenB, 1e17, 1);
        assertEq(amountIn, 100001);
    }

    function test_getMaximumAmountInOracleReverts() public {
        address tokenA = BaseGetter.getBaseERC20(6);
        address tokenB = BaseGetter.getBaseERC20(18);

        vm.mockCallRevert(address(priceSource), abi.encodeWithSelector(IPriceSource.getInBase.selector), "revert");
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_PRICE_SOURCE_GET_IN_BASE.selector);
        swapStrategy.getMaximumAmountIn(tokenA, tokenB, 1e6, SLIPPAGE);
    }
}
