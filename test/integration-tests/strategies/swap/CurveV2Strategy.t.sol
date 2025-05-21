// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ForkTest} from "../../../ForkTest.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {SwapRoutes} from "../../../utils/SwapRoutes.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {ISwapStrategy} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";

import {ICurveRouter} from "../../../../contracts/interfaces/external/strategy/swap/ICurveRouter.sol";

import {ChainlinkPrice} from "../../../../contracts/oracles/ChainlinkPrice.sol";
import {CurveV2Strategy} from "../../../../contracts/strategies/swap/CurveV2Strategy.sol";

contract CurveV2StrategyTest is ForkTest, TokensGenerator {
    CurveV2Strategy public curveV2Swap;
    ChainlinkPrice public priceSource;

    address public constant USDC = Constants.USDC;
    address public constant WETH = Constants.WETH;
    address public constant DAI = Constants.DAI;
    address public constant WBTC = Constants.WBTC;
    address public constant WSTETH = Constants.wstETH;
    address public constant USDT = Constants.USDT;
    address public constant CRV = Constants.CRV;
    address public constant CVX = Constants.CVX;
    address public constant crvUSD = Constants.crvUSD;

    uint256 public constant SLIPPAGE = 10_000; // 1%

    enum SwapRouteType {
        USDTToCRVUSD,
        CRVToUSDCMultihop,
        USDCToWETH,
        CRVToCrvUSD,
        CRVToUSDC,
        CVXToUSDC,
        CrvUSDToUSDC,
        USDCToCrvUSD,
        USDCToWETHMultihop
    }

    function setUp() public override {
        super.setUp();

        address[] memory assets = new address[](6);
        assets[0] = USDC;
        assets[1] = crvUSD;
        assets[2] = DAI;
        assets[3] = USDT;
        assets[4] = CRV;
        assets[5] = WETH;
        address[] memory toAssets = new address[](6);
        toAssets[0] = USDC;
        toAssets[1] = crvUSD;
        toAssets[2] = DAI;
        toAssets[3] = USDT;
        toAssets[4] = CRV;
        toAssets[5] = Constants.chainlink_ETH;

        priceSource = new ChainlinkPrice(
            FeedRegistryInterface(Constants.chainlink_FeedRegistry),
            assets,
            toAssets,
            Constants.chainlink_USD,
            60 * 60 * 24 * 2
        );

        curveV2Swap = new CurveV2Strategy(Constants.curve_Router, priceSource);
    }

    function test_ConstructedCorrectly() public view {
        assertEq(curveV2Swap.swapRouter(), Constants.curve_Router);
        assertEq(address(curveV2Swap.priceSource()), address(priceSource));
    }

    function test_SetSwapRoute() public {
        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).slippage, SLIPPAGE);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).route_tokens[0], USDT);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).route_tokens[1], crvUSD);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).pools[0], Constants.curve_Pool_USDT_crvUSD);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).swap_params[0][0], 0);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).swap_params[0][1], 1);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).swap_params[0][2], 1);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).swap_params[0][3], 1);
        assertEq(curveV2Swap.swapPairs(USDT, crvUSD).swap_params[0][4], 2);
    }

    function test_SetSwapRouteTooHighSlippage() public {
        (
            address[] memory routeTokens,
            address[] memory pools,
            uint256[5][] memory swapParams,
            CurveV2Strategy.PoolOracle[] memory pools_oracle
        ) = SwapRoutes.get_CurveUSDTToCRVUSD();

        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID.selector));

        curveV2Swap.setSwapPair(USDT, crvUSD, 10_000_001, routeTokens, pools, swapParams, pools_oracle);
    }

    function test_SetSwapRouteWrongRouteTokensLength() public {
        (
            ,
            address[] memory pools,
            uint256[5][] memory swapParams,
            CurveV2Strategy.PoolOracle[] memory pools_oracle
        ) = SwapRoutes.get_CurveUSDTToCRVUSD();

        address[] memory routeTokens = new address[](1);
        routeTokens[0] = Constants.USDT;
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID.selector));

        curveV2Swap.setSwapPair(USDT, crvUSD, SLIPPAGE, routeTokens, pools, swapParams, pools_oracle);
    }

    function test_SetSwapRouteWrongSwapParamsLength() public {
        (, , , CurveV2Strategy.PoolOracle[] memory pools_oracle) = SwapRoutes.get_CurveUSDTToCRVUSD();

        address[] memory routeTokens = new address[](3);
        routeTokens[0] = Constants.USDT;
        routeTokens[1] = Constants.USDT;
        routeTokens[2] = Constants.USDT;
        address[] memory pools = new address[](2);
        pools[0] = Constants.curve_Pool_USDT_crvUSD;
        pools[1] = Constants.curve_Pool_USDT_crvUSD;
        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(0), 1, 1, 1, 2];
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID.selector));

        curveV2Swap.setSwapPair(USDT, crvUSD, SLIPPAGE, routeTokens, pools, swapParams, pools_oracle);
    }

    function test_SetSwapRouteWrongPoolsOracleLength() public {
        (address[] memory routeTokens, address[] memory pools, uint256[5][] memory swapParams, ) = SwapRoutes
            .get_CurveUSDTToCRVUSD();

        CurveV2Strategy.PoolOracle[] memory pools_oracle;
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID.selector));

        curveV2Swap.setSwapPair(USDT, crvUSD, SLIPPAGE, routeTokens, pools, swapParams, pools_oracle);
    }

    function test_SetSwapRouteWrongAssetTo() public {
        (
            address[] memory routeTokens,
            address[] memory pools,
            uint256[5][] memory swapParams,
            CurveV2Strategy.PoolOracle[] memory pools_oracle
        ) = SwapRoutes.get_CurveUSDTToCRVUSD();

        // Set the last pool to WETH
        pools[pools.length - 1] = WETH;
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_INVALID_DESTINATION.selector));

        curveV2Swap.setSwapPair(USDT, WETH, SLIPPAGE, routeTokens, pools, swapParams, pools_oracle);
    }

    function test_SwapInUnknownPair() public {
        mintToken(USDT, address(this), 1e6);
        IToken(USDT).approve(address(curveV2Swap), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_UNKNOWN_PAIR.selector));

        curveV2Swap.swapInBase(USDT, crvUSD, 1e6);
    }

    function test_SwapInRouterRevert() public {
        vm.mockCallRevert(
            address(curveV2Swap.swapRouter()),
            abi.encodeWithSelector(ICurveRouter.exchange.selector),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );

        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        uint256 swapAmount = 10000e6;
        mintToken(USDT, address(this), swapAmount);
        IToken(USDT).approve(address(curveV2Swap), swapAmount);

        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_SWAP_NOT_PROCEEDED.selector);
        curveV2Swap.swapInBase(USDT, crvUSD, swapAmount);
    }

    function test_SwapInUSDTtoCRVUSD() public {
        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        uint256 swapAmount = 10000e6;
        mintToken(USDT, address(this), swapAmount);
        IToken(USDT).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(USDT, crvUSD, swapAmount);

        assertEq(IToken(USDT).balanceOf(address(this)), 0);
        assertGt(IToken(crvUSD).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(USDT, crvUSD, swapAmount, SLIPPAGE);
        assertGt(IToken(crvUSD).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapOutUSDTtoCRVUSD() public {
        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        uint256 swapAmountOut = 10000e18;
        uint256 maxAmountIn = curveV2Swap.getMaximumAmountIn(USDT, crvUSD, swapAmountOut);
        mintToken(USDT, address(this), maxAmountIn);
        IToken(USDT).approve(address(curveV2Swap), maxAmountIn);

        uint256 usdtBalanceBefore = IToken(USDT).balanceOf(address(this));
        curveV2Swap.swapOutBase(USDT, crvUSD, swapAmountOut, maxAmountIn);
        uint256 usdtBalanceAfter = IToken(USDT).balanceOf(address(this));
        assertLt(usdtBalanceBefore - usdtBalanceAfter, maxAmountIn);
        assertApproxEqAbs(IToken(crvUSD).balanceOf(address(this)), swapAmountOut, swapAmountOut / 10000);
        assertEq(IToken(USDT).allowance(address(curveV2Swap), curveV2Swap.swapRouter()), 0);
    }

    function test_AmountIn() public {
        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        uint256 amountOut = 100000e18;
        uint256 amountIn = curveV2Swap.getAmountIn(USDT, crvUSD, amountOut);
        uint256 reversePrice = priceSource.getInBase(USDT, crvUSD);
        uint256 expectedAmountIn = (amountOut * 10 ** 6) / reversePrice;

        // within 0.1%
        assertApproxEqAbs(amountIn, expectedAmountIn, 1e8);
    }

    function test_AmountIn_InvalidPair() public {
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_ROUTE_NOT_FOUND.selector, USDT, crvUSD));
        curveV2Swap.getAmountIn(USDT, crvUSD, 1e6);
    }

    function test_AmountOut() public {
        _setSwapRoute(USDT, crvUSD, SLIPPAGE, SwapRouteType.USDTToCRVUSD);

        uint256 amountIn = 100000e6;
        uint256 amountOut = curveV2Swap.getAmountOut(USDT, crvUSD, amountIn);

        uint256 reversePrice = priceSource.getInBase(USDT, crvUSD);
        uint256 expectedAmountOut = (amountIn * reversePrice) / 10 ** 6;

        // within 0.1%
        assertApproxEqAbs(amountOut, expectedAmountOut, 1e20);
    }

    function test_AmountOut_InvalidPair() public {
        vm.expectRevert(abi.encodeWithSelector(ISwapStrategy.SWAP_STRATEGY_ROUTE_NOT_FOUND.selector, USDT, crvUSD));
        curveV2Swap.getAmountOut(USDT, crvUSD, 1e6);
    }

    function test_SwapOutUSDCForWETH() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETHMultihop);

        uint256 amountOut = 1e18;
        uint256 maxAmountIn = curveV2Swap.getMaximumAmountIn(USDC, WETH, amountOut);
        mintToken(USDC, address(this), maxAmountIn);
        IToken(USDC).approve(address(curveV2Swap), maxAmountIn);

        // Swap X USDC for 1 WETH
        uint256 usdcBalanceBefore = IToken(USDC).balanceOf(address(this));
        curveV2Swap.swapOutBase(USDC, WETH, amountOut, maxAmountIn);
        uint256 usdcBalanceAfter = IToken(USDC).balanceOf(address(this));
        assertLt(usdcBalanceBefore - usdcBalanceAfter, maxAmountIn);

        // WETH balance after the swap within 1 BP
        assertApproxEqAbs(IToken(WETH).balanceOf(address(this)), amountOut, amountOut / 10000);
    }

    function test_SwapOutRouterRevert() public {
        vm.mockCallRevert(
            address(curveV2Swap.swapRouter()),
            abi.encodeWithSelector(ICurveRouter.exchange.selector),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETHMultihop);

        uint256 amountOut = 1e18;
        uint256 maxAmountIn = curveV2Swap.getMaximumAmountIn(USDC, WETH, amountOut);
        mintToken(USDC, address(this), maxAmountIn);
        IToken(USDC).approve(address(curveV2Swap), maxAmountIn);

        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_SWAP_NOT_PROCEEDED.selector);
        curveV2Swap.swapOutBase(USDC, WETH, amountOut, maxAmountIn);
    }

    function test_SwapOutUnknownPair() public {
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_UNKNOWN_PAIR.selector);
        curveV2Swap.swapOutBase(USDC, WETH, 1e18, 1e6);
    }

    function test_SwapOutNotEnoughAmountIn() public {
        _setSwapRoute(USDC, WETH, SLIPPAGE, SwapRouteType.USDCToWETHMultihop);

        uint256 amountOut = 1e18;
        vm.expectRevert(ISwapStrategy.SWAP_STRATEGY_SWAP_NOT_PROCEEDED.selector);
        curveV2Swap.swapOutBase(USDC, WETH, amountOut, 1e6);
    }

    function test_SwapCRVForCRVUSD() public {
        _setSwapRoute(CRV, crvUSD, SLIPPAGE, SwapRouteType.CRVToCrvUSD);

        uint256 swapAmount = 10000e18;
        mintToken(CRV, address(this), swapAmount);
        IToken(CRV).approve(address(curveV2Swap), swapAmount);

        // Swap 10000 CRV for crvUSD
        curveV2Swap.swapInBase(CRV, crvUSD, swapAmount);
        assertEq(IToken(CRV).balanceOf(address(this)), 0);
        assertGt(IToken(crvUSD).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(CRV, crvUSD, swapAmount, SLIPPAGE);
        assertGt(IToken(crvUSD).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapCRVForUSDC() public {
        _setSwapRoute(CRV, USDC, 12500, SwapRouteType.CRVToUSDC);

        uint256 swapAmount = 10000e18;
        mintToken(CRV, address(this), swapAmount);
        IToken(CRV).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(CRV, USDC, swapAmount);
        assertEq(IToken(CRV).balanceOf(address(this)), 0);
        assertGt(IToken(USDC).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(CRV, USDC, swapAmount, SLIPPAGE);
        assertGt(IToken(USDC).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapCVXForUSDC() public {
        _setSwapRoute(CVX, USDC, 20000, SwapRouteType.CVXToUSDC);

        uint256 swapAmount = 1e18;
        mintToken(CVX, address(this), swapAmount);
        IToken(CVX).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(CVX, USDC, swapAmount);
        assertEq(IToken(CVX).balanceOf(address(this)), 0);
        assertGt(IToken(USDC).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(CVX, USDC, swapAmount, SLIPPAGE);
        assertGt(IToken(USDC).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapCRVUSDForUSDC() public {
        _setSwapRoute(crvUSD, USDC, 600, SwapRouteType.CrvUSDToUSDC);

        uint256 swapAmount = 10000e18;
        mintToken(crvUSD, address(this), swapAmount);
        IToken(crvUSD).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(crvUSD, USDC, swapAmount);
        assertEq(IToken(crvUSD).balanceOf(address(this)), 0);
        assertGt(IToken(USDC).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(crvUSD, USDC, swapAmount, SLIPPAGE);
        assertGt(IToken(USDC).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapUSDCForCRVUSD() public {
        _setSwapRoute(USDC, crvUSD, 500, SwapRouteType.USDCToCrvUSD);

        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(USDC, crvUSD, swapAmount);
        assertEq(IToken(USDC).balanceOf(address(this)), 0);
        assertGt(IToken(crvUSD).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(USDC, crvUSD, swapAmount, SLIPPAGE);
        assertGt(IToken(crvUSD).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapUSDCForWETH() public {
        _setSwapRoute(USDC, WETH, 12500, SwapRouteType.USDCToWETH);

        uint256 swapAmount = 10000e6;
        mintToken(USDC, address(this), swapAmount);
        IToken(USDC).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(USDC, WETH, swapAmount);
        assertEq(IToken(USDC).balanceOf(address(this)), 0);
        assertGt(IToken(WETH).balanceOf(address(this)), 0);

        uint256 minAmountOut = curveV2Swap.getMinimumAmountOut(USDC, WETH, swapAmount, SLIPPAGE);
        assertGt(IToken(WETH).balanceOf(address(this)), minAmountOut);
    }

    function test_SwapCRVForUSDCMultihop() public {
        _setSwapRoute(CRV, USDC, 12500, SwapRouteType.CRVToUSDCMultihop);

        uint256 swapAmount = 10000e18;
        mintToken(CRV, address(this), swapAmount);
        IToken(CRV).approve(address(curveV2Swap), swapAmount);

        curveV2Swap.swapInBase(CRV, USDC, swapAmount);
        assertEq(IToken(CRV).balanceOf(address(this)), 0);
        assertGt(IToken(USDC).balanceOf(address(this)), 0);
    }

    function test_RouteSlippageReverts() public {
        vm.expectRevert();
        curveV2Swap.getMaximumAmountIn(USDC, WETH, 1e18);
    }

    function _setSwapRoute(
        address assetFrom,
        address assetTo,
        uint256 customSlippage,
        SwapRouteType routeType
    ) internal {
        (
            address[] memory routeTokens,
            address[] memory pools,
            uint256[5][] memory swapParams,
            CurveV2Strategy.PoolOracle[] memory pools_oracle
        ) = _getRoute(routeType);

        curveV2Swap.setSwapPair(assetFrom, assetTo, customSlippage, routeTokens, pools, swapParams, pools_oracle);
    }

    function _getRoute(
        SwapRouteType routeType
    )
        internal
        pure
        returns (
            address[] memory routeTokens,
            address[] memory pools,
            uint256[5][] memory swapParams,
            CurveV2Strategy.PoolOracle[] memory pools_oracle
        )
    {
        if (routeType == SwapRouteType.USDTToCRVUSD) {
            return SwapRoutes.get_CurveUSDTToCRVUSD();
        } else if (routeType == SwapRouteType.CRVToUSDCMultihop) {
            return SwapRoutes.get_CurveCRVToUSDCMultihop();
        } else if (routeType == SwapRouteType.USDCToWETH) {
            return SwapRoutes.get_CurveUSDCToWETH();
        } else if (routeType == SwapRouteType.CRVToCrvUSD) {
            return SwapRoutes.get_CurveCRVToCrvUSD();
        } else if (routeType == SwapRouteType.CRVToUSDC) {
            return SwapRoutes.get_CurveCRVToUSDC();
        } else if (routeType == SwapRouteType.CVXToUSDC) {
            return SwapRoutes.get_CurveCVXToUSDC();
        } else if (routeType == SwapRouteType.CrvUSDToUSDC) {
            return SwapRoutes.get_CurveCrvUSDToUSDC();
        } else if (routeType == SwapRouteType.USDCToCrvUSD) {
            return SwapRoutes.get_CurveUSDCToCrvUSD();
        } else if (routeType == SwapRouteType.USDCToWETHMultihop) {
            return SwapRoutes.get_CurveUSDCToWETHMultihop();
        }
    }
}
