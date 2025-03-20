// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/strategy/swap/ISwapStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./SwapStrategy.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
/// @dev Uniswap's V3 view Quoter
import "../../interfaces/external/strategy/swap/IQuoter.sol";

/**
 * @title UniswapV3Strategy
 * @dev UniswapV3 integration contract
 * @dev Process swaps between predefinded pairs
 * @author Altitude Labs
 **/

contract UniswapV3Strategy is SwapStrategy {
    struct SwapRoute {
        uint24 feeTier;
        address assetTo;
    }

    struct SwapData {
        bytes directPath;
        bytes inversePath;
        uint256 slippage; // 3000 - 0.3% at base 1e6 (Maximum Slippage per pair)
    }

    IQuoter public quoter;

    /** @notice Multihop route configurations */
    mapping(address => mapping(address => SwapData)) public swapPairs;

    constructor(
        address _router,
        IPriceSource _priceSource,
        IQuoter _quoter
    ) SwapStrategy(_router, _priceSource) {
        quoter = _quoter;
    }

    /**
     * @notice Set the Uniswap v3 view quoter address
     * @param _quoter Quoter contract address
     */
    function setQuoter(IQuoter _quoter) external onlyOwner {
        quoter = _quoter;
    }

    /**
     * @notice Set multihop swap configuration
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @param slippage Maximum slippage per swap pair
     * @param multiHop configuration struct
     */
    function setSwapPair(
        address assetFrom,
        address assetTo,
        uint256 slippage,
        SwapRoute[] memory multiHop
    ) external onlyOwner {
        // The last route address must be `assetTo`
        if (multiHop[multiHop.length - 1].assetTo != assetTo) {
            revert SWAP_STRATEGY_INVALID_DESTINATION();
        }

        uint256 newHopsLength = multiHop.length;

        bytes memory directPath = abi.encodePacked(
            abi.encodePacked(assetFrom),
            multiHop[0].feeTier,
            multiHop[0].assetTo
        );
        bytes memory inversePath = abi.encodePacked(
            multiHop[0].assetTo,
            multiHop[0].feeTier,
            abi.encodePacked(assetFrom)
        );

        for (uint256 i = 1; i < newHopsLength; ) {
            directPath = abi.encodePacked(directPath, multiHop[i].feeTier, multiHop[i].assetTo);

            inversePath = abi.encodePacked(multiHop[i].assetTo, multiHop[i].feeTier, inversePath);

            unchecked {
                ++i;
            }
        }

        swapPairs[assetFrom][assetTo].directPath = directPath;
        swapPairs[assetFrom][assetTo].inversePath = inversePath;
        swapPairs[assetFrom][assetTo].slippage = slippage;

        emit SwapPairSet(assetFrom, assetTo, slippage);
    }

    /**
     * @notice Single & Multihop Swap
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

        SwapData memory swapData = swapPairs[assetFrom][assetTo];
        if (swapData.directPath.length == 0) {
            revert SWAP_STRATEGY_UNKNOWN_PAIR();
        }

        uint256 minAmount;
        minAmount = getMinimumAmountOut(assetFrom, assetTo, amount, swapData.slippage);

        // Approve the router to spend `assetFrom`.
        TransferHelper.safeApprove(assetFrom, address(swapRouter), amount);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: swapData.directPath,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amount,
            amountOutMinimum: minAmount
        });

        try ISwapRouter(swapRouter).exactInput(params) returns (uint256 outputAmount) {
            amountOut = outputAmount;
        } catch {
            revert SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
        }

        emit SwapProceed(amountOut);
    }

    /**
     * @notice Single & Multihop Swap
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
        SwapData memory swapData = swapPairs[assetFrom][assetTo];
        if (swapData.inversePath.length == 0) {
            revert SWAP_STRATEGY_UNKNOWN_PAIR();
        }

        TransferHelper.safeTransferFrom(assetFrom, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend `assetFrom`.
        TransferHelper.safeApprove(assetFrom, address(swapRouter), amountInMaximum);
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: swapData.inversePath,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

        uint256 refundAmount;
        try ISwapRouter(swapRouter).exactOutput(params) returns (uint256 inputAmount) {
            amountIn = inputAmount;
            if (amountIn < amountInMaximum) {
                refundAmount = amountInMaximum - amountIn;
            }
        } catch {
            revert SWAP_STRATEGY_SWAP_NOT_PROCEEDED();
        }

        // Refund msg.sender if the swap require full `amountInMaximum`, and clear approval to swap router.
        if (refundAmount > 0) {
            IERC20(assetFrom).approve(address(swapRouter), 0);

            TransferHelper.safeTransfer(assetFrom, msg.sender, refundAmount);
        }

        emit SwapProceed(amountIn);
    }

    /**
     * @param assetFrom Inbound asset
     * @param assetTo Outbound Asset
     * @return slippage Swap strategy's slippage for this route
     */
    function _routeSlippage(address assetFrom, address assetTo) internal view override returns (uint256 slippage) {
        SwapData memory swapData = swapPairs[assetFrom][assetTo];
        if (swapData.directPath.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }

        slippage = swapPairs[assetFrom][assetTo].slippage;
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
        SwapData memory swapData = swapPairs[assetFrom][assetTo];
        if (swapData.directPath.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }

        (amountIn, , , ) = quoter.quoteExactOutput(swapData.inversePath, amountOut);
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
        SwapData memory swapData = swapPairs[assetFrom][assetTo];
        if (swapData.directPath.length == 0) {
            revert SWAP_STRATEGY_ROUTE_NOT_FOUND(assetFrom, assetTo);
        }

        (amountOut, , , ) = quoter.quoteExactInput(swapData.directPath, amountIn);
    }
}
