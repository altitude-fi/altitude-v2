// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/strategy/swap/ISwapStrategy.sol";
import "../../interfaces/external/strategy/swap/ICurveRouter.sol";
import "../../interfaces/external/strategy/farming/Curve/ICurve2.sol";
import "../../interfaces/external/strategy/farming/Curve/ICurve4.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./SwapStrategy.sol";
import "../../libraries/utils/Utils.sol";

/**
 * @title CurveV2Strategy
 * @dev CurveV2 integration contract
 * @dev Process swaps between predefinded pairs
 * @author Altitude Labs
 **/

contract CurveV2Strategy is ISwapStrategy, SwapStrategy {
    uint256 internal constant ROUNDING_ERROR_TOLERANCE = 1000;
    uint8 internal constant PRICE_ORACLE_DECIMALS = 18;

    enum PoolOracle {
        OnlyExternal,
        TwoCoin,
        ManyCoin
    }

    struct SwapData {
        address[] route_tokens;
        address[] pools;
        uint256[5][] swap_params;
        PoolOracle[] pools_oracle;
        uint256 slippage; // 3000 - 0.3% at base 1e6 (Maximum Slippage per pair)
    }

    /** @notice Multihop route configurations */
    mapping(address => mapping(address => SwapData)) internal _swapPairs;

    constructor(address _router, IPriceSource _priceSource) SwapStrategy(_router, _priceSource) {}

    /**
     * @notice Set multihop swap configuration
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param slippage Maximum slippage per swap pair
     */
    function setSwapPair(
        address assetFrom,
        address assetTo,
        uint256 slippage,
        address[] calldata _route_tokens,
        address[] calldata _pools,
        uint256[5][] calldata _swap_params,
        PoolOracle[] calldata _pools_oracle
    ) external onlyOwner {
        if (slippage > SLIPPAGE_BASE) {
            revert SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID();
        }
        if (_route_tokens.length != _pools.length + 1) {
            revert SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID();
        }
        if (_pools.length != _swap_params.length) {
            revert SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID();
        }
        if (_route_tokens[_route_tokens.length - 1] != assetTo) {
            revert SWAP_STRATEGY_INVALID_DESTINATION();
        }
        if (_pools.length != _pools_oracle.length) {
            revert SWAP_STRATEGY_SET_SWAP_PAIR_INPUT_INVALID();
        }

        _swapPairs[assetFrom][assetTo].slippage = slippage;
        _swapPairs[assetFrom][assetTo].route_tokens = _route_tokens;
        _swapPairs[assetFrom][assetTo].pools = _pools;
        _swapPairs[assetFrom][assetTo].swap_params = _swap_params;
        _swapPairs[assetFrom][assetTo].pools_oracle = _pools_oracle;

        emit SwapPairSet(assetFrom, assetTo, slippage);
    }

    /** @notice swapPairs getter
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     **/
    function swapPairs(address assetFrom, address assetTo) external view returns (SwapData memory) {
        return _swapPairs[assetFrom][assetTo];
    }

    /**
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amount Swap amount of inbound asset
     * @return amountOut
     */
    function swapInBase(
        address assetFrom,
        address assetTo,
        uint256 amount
    ) external override returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(assetFrom, msg.sender, address(this), amount);
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];

        if (swapData.pools.length == 0) {
            revert SWAP_STRATEGY_UNKNOWN_PAIR();
        }

        uint256 minAmount;
        minAmount = getMinimumAmountOut(assetFrom, assetTo, amount, swapData.slippage);

        /// @notice Approve the router to spend `assetFrom`.
        TransferHelper.safeApprove(assetFrom, swapRouter, amount);

        /// @notice prepare parameters for ICurveRouter(swapRouter).exchange
        (address[11] memory route, uint256[5][5] memory swapParams, address[5] memory pools) = _prepareSwapParameters(
            swapData
        );

        try ICurveRouter(swapRouter).exchange(route, swapParams, amount, minAmount, pools, msg.sender) returns (
            uint256 outputAmount
        ) {
            amountOut = outputAmount;
        } catch {
            revert SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
        }

        emit SwapProceed(amountOut);
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
        uint256 baseAmount,
        uint256 slippage
    ) public view override(ISwapStrategy, SwapStrategy) returns (uint256) {
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];
        uint256 poolsLength = swapData.pools.length;

        uint256 price = 10**PRICE_ORACLE_DECIMALS;
        for (uint256 i; i < poolsLength; ++i) {
            PoolOracle useOracle = swapData.pools_oracle[i];
            if (useOracle > PoolOracle.OnlyExternal) {
                // if using curve's oracle for this pool
                uint256 priceInput = 10**PRICE_ORACLE_DECIMALS;
                uint256 priceOutput = 10**PRICE_ORACLE_DECIMALS;
                if (useOracle == PoolOracle.TwoCoin) {
                    if (swapData.swap_params[i][0] > 0) {
                        priceInput = ICurve2(swapData.pools[i]).price_oracle();
                    } else {
                        priceOutput = ICurve2(swapData.pools[i]).price_oracle();
                    }
                } else {
                    // if n coin pool
                    if (swapData.swap_params[i][0] > 0) {
                        priceInput = ICurve4(swapData.pools[i]).price_oracle(swapData.swap_params[i][0] - 1);
                    }
                    if (swapData.swap_params[i][1] > 0) {
                        priceOutput = ICurve4(swapData.pools[i]).price_oracle(swapData.swap_params[i][1] - 1);
                    }
                }
                price =
                    (price * ((priceInput * (10**PRICE_ORACLE_DECIMALS)) / priceOutput)) /
                    (10**PRICE_ORACLE_DECIMALS);
            } else {
                // PoolOracle.OnlyExternal - use external oracle for the whole path
                return SwapStrategy.getMinimumAmountOut(assetFrom, assetTo, baseAmount, slippage);
            }
        }

        return (
            _applySlippage(
                Utils.scaleAmount(
                    baseAmount * price,
                    IERC20Metadata(assetFrom).decimals() + PRICE_ORACLE_DECIMALS,
                    IERC20Metadata(assetTo).decimals()
                ),
                slippage
            )
        );
    }

    /**
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amountOut Swap amount of outbound asset
     * @param amountInMaximum The amount of inbound asset willing to spend to receive the specified `amountOut`
     * @return amountIn
     */
    function swapOutBase(
        address assetFrom,
        address assetTo,
        uint256 amountOut,
        uint256 amountInMaximum
    ) external override returns (uint256 amountIn) {
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];
        if (swapData.pools.length == 0) {
            revert SWAP_STRATEGY_UNKNOWN_PAIR();
        }
        (address[11] memory route, uint256[5][5] memory swapParams, address[5] memory pools) = _prepareSwapParameters(
            swapData
        );

        /// @dev accounting for rounding errors
        amountIn = ICurveRouter(swapRouter).get_dx(route, swapParams, amountOut, pools) + ROUNDING_ERROR_TOLERANCE;
        if (amountIn > amountInMaximum) {
            revert SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
        }
        TransferHelper.safeTransferFrom(assetFrom, msg.sender, address(this), amountIn);

        // Approve the router to spend `assetFrom`.
        TransferHelper.safeApprove(assetFrom, swapRouter, amountIn);
        try ICurveRouter(swapRouter).exchange(route, swapParams, amountIn, amountOut, pools, msg.sender) returns (
            uint256 outputAmount
        ) {
            amountOut = outputAmount;
        } catch {
            revert SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
        }
        TransferHelper.safeApprove(assetFrom, swapRouter, 0);

        emit SwapProceed(amountIn);
    }

    function _prepareSwapParameters(SwapData storage swapData)
        internal
        view
        returns (
            address[11] memory route,
            uint256[5][5] memory swapParams,
            address[5] memory pools
        )
    {
        uint256 routeIdx;
        uint256 poolsLength = swapData.pools.length;
        //@dev last token pushed after the loop as there is one pool less than tokens
        for (uint256 i; i < poolsLength; ++i) {
            // route
            route[routeIdx] = swapData.route_tokens[i];
            ++routeIdx;
            route[routeIdx] = swapData.pools[i];
            ++routeIdx;
            // pools
            pools[i] = swapData.pools[i];
            //params
            swapParams[i] = swapData.swap_params[i];
        }
        route[routeIdx] = swapData.route_tokens[poolsLength];
    }

    /**
     * @notice Computes the amount of assetFrom needed to acquire `amountOut`
     * @dev Uses pre-set swap path.
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amountOut Desired output amount
     * @return amountIn Amount of assetFrom needed
     */
    function getAmountIn(
        address assetFrom,
        address assetTo,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];

        if (swapData.pools.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }
        (address[11] memory route, uint256[5][5] memory swapParams, address[5] memory pools) = _prepareSwapParameters(
            swapData
        );

        amountIn = ICurveRouter(swapRouter).get_dx(route, swapParams, amountOut, pools) + ROUNDING_ERROR_TOLERANCE;
    }

    /**
     * @notice Computes the amount of assetTo recieved by swapping `amountIn`
     * @dev Uses pre-set swap path.
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param amountIn Intended input amount
     * @return amountOut Amount of assetTo returned
     */
    function getAmountOut(
        address assetFrom,
        address assetTo,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];
        if (swapData.pools.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }

        (address[11] memory route, uint256[5][5] memory swapParams, address[5] memory pools) = _prepareSwapParameters(
            swapData
        );

        amountOut = ICurveRouter(swapRouter).get_dy(route, swapParams, amountIn, pools) + ROUNDING_ERROR_TOLERANCE;
    }

    /**
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @return slippage Swap strategy's slippage for this route
     */
    function _routeSlippage(address assetFrom, address assetTo) internal view override returns (uint256 slippage) {
        SwapData storage swapData = _swapPairs[assetFrom][assetTo];
        if (swapData.pools.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }

        slippage = _swapPairs[assetFrom][assetTo].slippage;
    }
}
