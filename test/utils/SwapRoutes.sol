pragma solidity 0.8.28;

import {Constants} from "../../scripts/deployer/Constants.sol";

import {CurveV2Strategy} from "../../contracts/strategies/swap/CurveV2Strategy.sol";
import {UniswapV3Strategy} from "../../contracts/strategies/swap/UniswapV3Strategy.sol";

library SwapRoutes {
    // UniswapV3 purpose
    function get_UniswapDAIToWBTC() public pure returns (UniswapV3Strategy.SwapRoute[] memory) {
        // {DAI -> USDC(tier 100) -> WETH(tier 500) -> WBTC(tier 500)}

        UniswapV3Strategy.SwapRoute[] memory path = new UniswapV3Strategy.SwapRoute[](3);

        path[0] = UniswapV3Strategy.SwapRoute({assetTo: Constants.USDC, feeTier: Constants.uniswap_v3_FeeTier_100});
        path[1] = UniswapV3Strategy.SwapRoute({assetTo: Constants.WETH, feeTier: Constants.uniswap_v3_FeeTier_500});
        path[2] = UniswapV3Strategy.SwapRoute({assetTo: Constants.WBTC, feeTier: Constants.uniswap_v3_FeeTier_500});

        return path;
    }

    // UniswapV3 purpose
    function get_UniswapUSDCToWETH() public pure returns (UniswapV3Strategy.SwapRoute[] memory) {
        // {USDC -> WETH(tier 3000) }

        UniswapV3Strategy.SwapRoute[] memory path = new UniswapV3Strategy.SwapRoute[](1);

        path[0] = UniswapV3Strategy.SwapRoute({assetTo: Constants.WETH, feeTier: Constants.uniswap_v3_FeeTier_3000});

        return path;
    }

    // UniswapV3 purpose
    function get_UniswapUSDCToWSTETH() public pure returns (UniswapV3Strategy.SwapRoute[] memory) {
        // {USDC -> WETH(tier 500) -> WSTETH(tier 100) }

        UniswapV3Strategy.SwapRoute[] memory path = new UniswapV3Strategy.SwapRoute[](2);

        path[0] = UniswapV3Strategy.SwapRoute({assetTo: Constants.WETH, feeTier: Constants.uniswap_v3_FeeTier_500});

        path[1] = UniswapV3Strategy.SwapRoute({assetTo: Constants.wstETH, feeTier: Constants.uniswap_v3_FeeTier_100});

        return path;
    }

    // CurveV2 purpose
    function get_CurveUSDTToCRVUSD()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {USDT -> CRVUSD}
        address[] memory routeTokens = new address[](2);
        routeTokens[0] = Constants.USDT;
        routeTokens[1] = Constants.crvUSD;

        address[] memory pools = new address[](1);
        pools[0] = Constants.curve_Pool_USDT_crvUSD;

        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(0), 1, 1, 1, 2];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](1);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.OnlyExternal;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveUSDCToWETHMultihop()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {USDC -> USDT -> WETH}
        address[] memory routeTokens = new address[](3);
        routeTokens[0] = Constants.USDC;
        routeTokens[1] = Constants.USDT;
        routeTokens[2] = Constants.WETH;

        address[] memory pools = new address[](2);
        pools[0] = Constants.curve_Pool_3;
        pools[1] = Constants.curve_Pool_Tricrypto2;

        uint256[5][] memory swapParams = new uint256[5][](2);
        swapParams[0] = [uint256(1), 2, 1, 1, 3];
        swapParams[1] = [uint256(0), 2, 1, 3, 3];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](2);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.OnlyExternal;
        pools_oracle[1] = CurveV2Strategy.PoolOracle.OnlyExternal;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveCRVToCrvUSD()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {CRV -> CrvUSD}
        address[] memory routeTokens = new address[](2);
        routeTokens[0] = Constants.CRV;
        routeTokens[1] = Constants.crvUSD;

        address[] memory pools = new address[](1);
        pools[0] = Constants.curve_Pool_TriCRV;

        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(2), 0, 1, 3, 3];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](1);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.ManyCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveCRVToUSDC()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {CRV -> CrvUSD -> USDC}
        address[] memory routeTokens = new address[](3);
        routeTokens[0] = Constants.CRV;
        routeTokens[1] = Constants.crvUSD;
        routeTokens[2] = Constants.USDC;

        address[] memory pools = new address[](2);
        pools[0] = Constants.curve_Pool_TriCRV;
        pools[1] = Constants.curve_Pool_USDC_crvUSD;

        uint256[5][] memory swapParams = new uint256[5][](2);
        swapParams[0] = [uint256(2), 0, 1, 3, 3];
        swapParams[1] = [uint256(1), 0, 1, 1, 2];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](2);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.ManyCoin;
        pools_oracle[1] = CurveV2Strategy.PoolOracle.TwoCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveCVXToUSDC()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {CVX -> ETH -> USDC}
        address[] memory routeTokens = new address[](3);
        routeTokens[0] = Constants.CVX;
        routeTokens[1] = Constants.WETH;
        routeTokens[2] = Constants.USDC;

        address[] memory pools = new address[](2);
        pools[0] = Constants.curve_Pool_cvxETH;
        pools[1] = Constants.curve_Pool_Tricrypto_USDC;

        uint256[5][] memory swapParams = new uint256[5][](2);
        swapParams[0] = [uint256(1), 0, 1, 2, 2];
        swapParams[1] = [uint256(2), 0, 1, 3, 3];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](2);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.TwoCoin;
        pools_oracle[1] = CurveV2Strategy.PoolOracle.ManyCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveCrvUSDToUSDC()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {CrvUSD -> USDC}
        address[] memory routeTokens = new address[](2);
        routeTokens[0] = Constants.crvUSD;
        routeTokens[1] = Constants.USDC;

        address[] memory pools = new address[](1);
        pools[0] = Constants.curve_Pool_USDC_crvUSD;

        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(1), 0, 1, 1, 2];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](1);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.TwoCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveUSDCToCrvUSD()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {USDC -> CrvUSD}
        address[] memory routeTokens = new address[](2);
        routeTokens[0] = Constants.USDC;
        routeTokens[1] = Constants.crvUSD;

        address[] memory pools = new address[](1);
        pools[0] = Constants.curve_Pool_USDC_crvUSD;

        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(0), 1, 1, 1, 2];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](1);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.TwoCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveUSDCToWETH()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {USDC -> WETH}
        address[] memory routeTokens = new address[](2);
        routeTokens[0] = Constants.USDC;
        routeTokens[1] = Constants.WETH;

        address[] memory pools = new address[](1);
        pools[0] = Constants.curve_Pool_Tricrypto_USDC;

        uint256[5][] memory swapParams = new uint256[5][](1);
        swapParams[0] = [uint256(0), 2, 1, 3, 3];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](1);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.ManyCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }

    // CurveV2 purpose
    function get_CurveCRVToUSDCMultihop()
        public
        pure
        returns (
            address[] memory,
            address[] memory,
            uint256[5][] memory,
            CurveV2Strategy.PoolOracle[] memory
        )
    {
        // {CRV -> CrvUSD -> USDC}
        address[] memory routeTokens = new address[](3);
        routeTokens[0] = Constants.CRV;
        routeTokens[1] = Constants.crvUSD;
        routeTokens[2] = Constants.USDC;

        address[] memory pools = new address[](2);
        pools[0] = Constants.curve_Pool_TriCRV;
        pools[1] = Constants.curve_Pool_USDC_crvUSD;

        uint256[5][] memory swapParams = new uint256[5][](2);
        swapParams[0] = [uint256(2), 0, 1, 3, 3];
        swapParams[1] = [uint256(1), 0, 1, 1, 2];

        CurveV2Strategy.PoolOracle[] memory pools_oracle = new CurveV2Strategy.PoolOracle[](2);
        pools_oracle[0] = CurveV2Strategy.PoolOracle.ManyCoin;
        pools_oracle[1] = CurveV2Strategy.PoolOracle.TwoCoin;

        return (routeTokens, pools, swapParams, pools_oracle);
    }
}
