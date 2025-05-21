// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ForkTest} from "../../../ForkTest.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {SwapRoutes} from "../../../utils/SwapRoutes.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {IQuoter} from "../../../../contracts/interfaces/external/strategy/swap/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ISwapStrategy} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";

import {ChainlinkPrice} from "../../../../contracts/oracles/ChainlinkPrice.sol";
import {UniswapV3Strategy} from "../../../../contracts/strategies/swap/UniswapV3Strategy.sol";

contract UniswapV3StrategyTest is ForkTest, TokensGenerator {
    UniswapV3Strategy public uniswapV3Swap;
    ChainlinkPrice public priceSource;
    ISwapRouter public swapRouter;

    address public constant USDC = Constants.USDC;
    address public constant WETH = Constants.WETH;
    address public constant DAI = Constants.DAI;
    address public constant WBTC = Constants.WBTC;
    address public constant WSTETH = Constants.wstETH;

    uint256 public constant SLIPPAGE = 10_000; // 1%
    uint256 public constant SLIPPAGE_BASE = 1_000_000; // 100%

    enum SwapRouteType {
        DAIToWBTC,
        USDCToWETH,
        USDCToWSTETH
    }

    function setUp() public override {
        super.setUp();

        swapRouter = ISwapRouter(Constants.uniswap_v3_SwapRouter);
        address[] memory assets = new address[](2);
        assets[0] = WBTC;
        assets[1] = WETH;
        address[] memory toAssets = new address[](2);
        toAssets[0] = Constants.chainlink_BTC;
        toAssets[1] = Constants.chainlink_ETH;
        priceSource = new ChainlinkPrice(
            FeedRegistryInterface(Constants.chainlink_FeedRegistry),
            assets,
            toAssets,
            Constants.chainlink_USD,
            60 * 60 * 24 * 2
        );
        uniswapV3Swap = new UniswapV3Strategy(
            address(swapRouter),
            priceSource,
            IQuoter(Constants.uniswap_v3_ViewQuoter)
        );
    }

    function test_ConstructedCorrectly() public view {
        assertEq(address(uniswapV3Swap.swapRouter()), address(swapRouter));
        assertTrue(address(uniswapV3Swap.priceSource()) != address(0));
    }

    function test_UpdatePriceSource() public {
        uniswapV3Swap.setPriceSource(address(0));
        assertEq(address(uniswapV3Swap.priceSource()), address(0));
    }

    function test_SetInvalidMultihopSwapRoute() public {
        UniswapV3Strategy.SwapRoute[] memory path = SwapRoutes.get_UniswapDAIToWBTC();

        path[2].assetTo = Constants.USDC;

        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_INVALID_DESTINATION.selector);
        uniswapV3Swap.setSwapPair(DAI, WBTC, SLIPPAGE, path);
    }

    function test_SetValidMultihopSwapRoute() public {
        _setSwapRoute(DAI, WBTC, SLIPPAGE, SwapRouteType.DAIToWBTC);

        (bytes memory directPath, bytes memory inversePath, uint256 slippage) = uniswapV3Swap.swapPairs(DAI, WBTC);

        assertTrue(directPath.length > 0);
        assertTrue(inversePath.length > 0);
        assertEq(slippage, SLIPPAGE);
    }

    function test_SwapInForNotExistingPair() public {
        mintToken(DAI, address(this), 1000);
        IToken(DAI).approve(address(uniswapV3Swap), 1000);

        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_UNKNOWN_PAIR.selector);
        uniswapV3Swap.swapInBase(DAI, WBTC, 1000);
    }

    function test_SingleSwapInUSDCForWETH() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);

        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(uniswapV3Swap), swapAmount);

        uniswapV3Swap.swapInBase(USDC, WETH, swapAmount);

        assertEq(IToken(USDC).balanceOf(address(this)), 0);
        assertGt(IToken(WETH).balanceOf(address(this)), 0);
    }

    function test_MultihopSwapInDaiForWbtc() public {
        uint256 swapAmount = 100000e18;
        _setSwapRoute(DAI, WBTC, SLIPPAGE, SwapRouteType.DAIToWBTC);

        mintToken(DAI, address(this), swapAmount);
        IToken(DAI).approve(address(uniswapV3Swap), swapAmount);

        uniswapV3Swap.swapInBase(DAI, WBTC, swapAmount);

        assertEq(IToken(DAI).balanceOf(address(this)), 0);
        assertGt(IToken(WBTC).balanceOf(address(this)), 0);

        // Swap with exact output
        mintToken(DAI, address(this), swapAmount);
        IToken(DAI).approve(address(uniswapV3Swap), swapAmount);

        uint256 balanceWBTCBefore = IToken(WBTC).balanceOf(address(this));
        uniswapV3Swap.swapOutBase(DAI, WBTC, 1e8, swapAmount);
        uint256 balanceWBTCAfter = IToken(WBTC).balanceOf(address(this));
        assertEq(balanceWBTCAfter - balanceWBTCBefore, 1e8);
    }

    function test_MultihopSwapInUSDCForWSTETH() public {
        _setSwapRoute(USDC, WSTETH, SLIPPAGE, SwapRouteType.USDCToWSTETH);

        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(uniswapV3Swap), swapAmount);
        uniswapV3Swap.swapInBase(USDC, WSTETH, swapAmount);

        assertEq(IToken(USDC).balanceOf(address(this)), 0);
        assertGt(IToken(WSTETH).balanceOf(address(this)), 0);
    }

    function test_SwapInRouterRevert() public {
        vm.mockCallRevert(
            address(swapRouter),
            abi.encodeWithSelector(ISwapRouter.exactInput.selector),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        _setSwapRoute(USDC, WSTETH, SLIPPAGE, SwapRouteType.USDCToWSTETH);

        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(uniswapV3Swap), swapAmount);
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_SWAP_NOT_PROCEEDED.selector);
        uniswapV3Swap.swapInBase(USDC, WSTETH, swapAmount);
    }

    function test_SingleSwapOutUSDCForWETH() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);

        uint256 amountOut = 1e18;
        uint256 maxAmountIn = uniswapV3Swap.getMaximumAmountIn(USDC, WETH, amountOut);
        mintToken(USDC, address(this), maxAmountIn);
        IToken(USDC).approve(address(uniswapV3Swap), maxAmountIn);

        uint256 balanceUSDCBefore = IToken(USDC).balanceOf(address(this));
        uniswapV3Swap.swapOutBase(USDC, WETH, amountOut, maxAmountIn);
        uint256 balanceUSDCAfter = IToken(USDC).balanceOf(address(this));
        assertLt(balanceUSDCBefore - balanceUSDCAfter, maxAmountIn);

        assertEq(IToken(WETH).balanceOf(address(this)), amountOut);
        assertEq(IToken(USDC).allowance(address(this), address(uniswapV3Swap)), 0);
        assertEq(IToken(USDC).balanceOf(address(uniswapV3Swap)), 0);
        assertEq(IToken(WETH).balanceOf(address(uniswapV3Swap)), 0);
    }

    function test_SwapOutRefund() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);

        uint256 amountOut = 1e18;
        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(uniswapV3Swap), swapAmount);

        uniswapV3Swap.swapOutBase(USDC, WETH, amountOut, swapAmount);
        assertGt(IToken(USDC).balanceOf(address(this)), 0);
        assertEq(IToken(WETH).balanceOf(address(this)), amountOut);
    }

    function test_SwapOutRouterRevert() public {
        vm.mockCallRevert(
            address(swapRouter),
            abi.encodeWithSelector(ISwapRouter.exactOutput.selector),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);

        uint256 amountOut = 1e18;
        uint256 swapAmount = 1e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(uniswapV3Swap), swapAmount);

        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_SWAP_NOT_PROCEEDED.selector);
        uniswapV3Swap.swapOutBase(USDC, WETH, amountOut, swapAmount);
    }

    function test_SwapOutUnknownPair() public {
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_UNKNOWN_PAIR.selector);
        uniswapV3Swap.swapOutBase(USDC, WETH, 1e18, 1e6);
    }

    function test_AmountOutSingleHop() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);

        uint256 amountOut = uniswapV3Swap.getAmountOut(USDC, WETH, 10000e6);
        assertGt(amountOut, 0);
    }

    function test_AmountOutMultiHop() public {
        _setSwapRoute(DAI, WBTC, SLIPPAGE, SwapRouteType.DAIToWBTC);
        uint256 amountOut = uniswapV3Swap.getAmountOut(DAI, WBTC, 10000e18);
        assertGt(amountOut, 0);
    }

    function test_AmountOutUnknownPair() public {
        vm.expectRevert();
        uniswapV3Swap.getAmountOut(USDC, WETH, 10e18);
    }

    function test_AmountInSingleHop() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETH);
        uint256 amountIn = uniswapV3Swap.getAmountIn(USDC, WETH, 10e18);
        assertGt(amountIn, 0);
    }

    function test_AmountInMultiHop() public {
        _setSwapRoute(DAI, WBTC, SLIPPAGE, SwapRouteType.DAIToWBTC);
        uint256 amountIn = uniswapV3Swap.getAmountIn(DAI, WBTC, 10e8);
        assertGt(amountIn, 0);
    }

    function test_AmountInUnknownPair() public {
        vm.expectRevert();
        uniswapV3Swap.getAmountIn(USDC, WETH, 10e18);
    }

    function test_SetQuoter() public {
        uniswapV3Swap.setQuoter(IQuoter(address(0)));
        assertEq(address(uniswapV3Swap.quoter()), address(0));
    }

    function test_SetQuoterUnauthorized() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(vm.addr(1));
        uniswapV3Swap.setQuoter(IQuoter(address(0)));
    }

    function test_SetSwapPairUnauthorized() public {
        UniswapV3Strategy.SwapRoute[] memory path = SwapRoutes.get_UniswapUSDCToWETH();

        vm.prank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        uniswapV3Swap.setSwapPair(USDC, WETH, SLIPPAGE, path);
    }

    function test_SetPriceSourceUnauthorized() public {
        vm.prank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        uniswapV3Swap.setPriceSource(address(0));
    }

    function _setSwapRoute(
        address assetFrom,
        address assetTo,
        uint256 customSlippage,
        SwapRouteType routeType
    ) internal {
        UniswapV3Strategy.SwapRoute[] memory path = _getRoute(routeType);
        uniswapV3Swap.setSwapPair(assetFrom, assetTo, customSlippage, path);
    }

    function _getRoute(SwapRouteType routeType) internal pure returns (UniswapV3Strategy.SwapRoute[] memory route) {
        if (routeType == SwapRouteType.DAIToWBTC) {
            route = SwapRoutes.get_UniswapDAIToWBTC();
        } else if (routeType == SwapRouteType.USDCToWETH) {
            route = SwapRoutes.get_UniswapUSDCToWETH();
        } else if (routeType == SwapRouteType.USDCToWSTETH) {
            route = SwapRoutes.get_UniswapUSDCToWSTETH();
        }
    }

    function test_RouteSlippageReverts() public {
        vm.expectRevert();
        uniswapV3Swap.getMaximumAmountIn(USDC, WETH, 1e18);
    }
}
