// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../interfaces/internal/oracles/IPriceSource.sol";
import "../libraries/uniswap-v3/OracleLibrary.sol";
import "../libraries/uniswap-v3/PoolAddress.sol";

/**
 * @title UniswapV3Twap
 * @notice Get Uniswap V3 TWAP (Time Weighted Average Price)
 * @author Altitude Labs
 **/

contract UniswapV3Twap is IPriceSource, Ownable {
    // Uniswap V3 Twap Errors
    error UV3_TWAP_INVALID_FEE();
    error UV3_TWAP_ZERO_TIME_INTERVAL();
    error UV3_TWAP_INVALID_DESTINATION();
    error UV3_TWAP_PAIR_DOES_NOT_EXISTS();

    /** @notice UniswapV3 Factory address */
    address public immutable factory;

    /** @notice TWAP interval */
    uint32 public TWAP_INTERVAL;

    struct PairRoute {
        uint24 feeTier;
        address assetTo;
    }

    /** @notice Multihop route configurations */
    mapping(address => mapping(address => PairRoute[])) public oraclePairs;

    /** @notice Emitted when new TWAP interval is set */
    event TwapIntervalUpdated(uint32 twapInterval);

    /** @notice Emitted when new Oracle Pair is added */
    event SetOraclePair(address assetFrom, address assetTo);

    /** @notice Emitted when an Oracle Pair is removed */
    event RemoveOraclePair(address assetFrom, address assetTo);

    /** @notice Construct and initialize the UniswapV3 TWAP **/
    constructor(address _factory, uint32 twapInterval) Ownable() {
        factory = _factory;
        if (twapInterval == 0) {
            revert UV3_TWAP_ZERO_TIME_INTERVAL();
        }

        TWAP_INTERVAL = twapInterval;
    }

    /**
     * @notice Updates the TWAP interval
     * @param twapInterval TWAP interval in seconds
     */
    function setTwapInterval(uint32 twapInterval) external onlyOwner {
        if (twapInterval == 0) {
            revert UV3_TWAP_ZERO_TIME_INTERVAL();
        }

        TWAP_INTERVAL = twapInterval;
        emit TwapIntervalUpdated(twapInterval);
    }

    /**
     * @notice Updates the UniswapV3 Oracle Pair
     * @param assetFrom The asset the amount will be converted from
     * @param assetTo The asset the amount will be returned to
     * @param multiHop configuration struct
     */
    function setOraclePair(address assetFrom, address assetTo, PairRoute[] memory multiHop) external onlyOwner {
        delete oraclePairs[assetFrom][assetTo];

        uint256 newHopsLength = multiHop.length;
        if (newHopsLength == 0) {
            emit RemoveOraclePair(assetFrom, assetTo);
        } else if (multiHop[newHopsLength - 1].assetTo != assetTo) {
            revert UV3_TWAP_INVALID_DESTINATION();
        } else {
            // Update pair routes
            for (uint256 i; i < newHopsLength; ) {
                _validateFeeTier(multiHop[i].feeTier);
                oraclePairs[assetFrom][assetTo].push(PairRoute(multiHop[i].feeTier, multiHop[i].assetTo));
                unchecked {
                    ++i;
                }
            }
            emit SetOraclePair(assetFrom, assetTo);
        }
    }

    /** @notice check if fee tier is valid
     * @param feeTier fee tier to be checked
     */
    function _validateFeeTier(uint24 feeTier) internal view {
        int24 feeAmountTickSpacing = IUniswapV3Factory(factory).feeAmountTickSpacing(feeTier);
        if (feeAmountTickSpacing <= 0) {
            revert UV3_TWAP_INVALID_FEE();
        }
    }

    /**
     * @notice Price of 1 `fromAsset` in USD, using 6 decimal count
     * @dev This price oracle doesn't support pricing in USD
     */
    function getInUSD(address) external pure override returns (uint256) {
        revert UV3_TWAP_PAIR_DOES_NOT_EXISTS();
    }

    /**
     * @notice Returns the TWAP price for UnsiwapV3 Pair
     * @return toAssetAmount Represents 1 fromAsset in toAsset
     */
    function getInBase(address fromAsset, address toAsset) external view override returns (uint256 toAssetAmount) {
        // Get pair route
        PairRoute[] memory pairRoute = oraclePairs[fromAsset][toAsset];
        uint256 pairRouteLength = pairRoute.length;
        if (pairRouteLength == 0) {
            revert UV3_TWAP_PAIR_DOES_NOT_EXISTS();
        }

        // set toAssetAmount, base on fromAsset decimals
        toAssetAmount = 10 ** IERC20Metadata(fromAsset).decimals();

        // Get oracle price for each step in route
        for (uint256 i; i < pairRouteLength; ) {
            address poolAddress = PoolAddress.computeAddress(
                factory,
                PoolAddress.getPoolKey(fromAsset, pairRoute[i].assetTo, pairRoute[i].feeTier)
            );

            (int24 arithmeticMeanTick, ) = OracleLibrary.consult(poolAddress, TWAP_INTERVAL);

            toAssetAmount = OracleLibrary.getQuoteAtTick(
                arithmeticMeanTick,
                uint128(toAssetAmount),
                fromAsset,
                pairRoute[i].assetTo
            );
            fromAsset = pairRoute[i].assetTo;

            unchecked {
                ++i;
            }
        }
    }
}
