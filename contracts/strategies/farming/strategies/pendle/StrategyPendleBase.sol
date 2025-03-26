// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../FarmDropStrategy.sol";
import "../../../SkimStrategy.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "@pendle/core-v2/contracts/interfaces/IPPYLpOracle.sol";
import "@pendle/core-v2/contracts/interfaces/IPRouterStatic.sol";

import "../../../../interfaces/internal/strategy/farming/IPendleFarmStrategy.sol";

/**
 * @title StrategyPendleBase Contract
 * @dev Contract for interacting with Pendle protocol
 * @author Altitude Labs
 **/

abstract contract StrategyPendleBase is FarmDropStrategy, SkimStrategy, IPendleFarmStrategy {
    IPAllActionV3 public immutable router;
    IPRouterStatic public immutable routerStatic;
    IPPYLpOracle public immutable oracle;
    IPMarket public immutable market;
    IStandardizedYield public immutable SY;
    IPPrincipalToken public immutable PT;
    IPYieldToken public immutable YT;
    /// @dev Pendle exchange rates are 18 decimals. We need to mind the underlying decimals.
    uint8 internal immutable SY_DECIMALS;

    uint256 public constant SLIPPAGE_BASE = 1_000_000;
    /// @notice Price slippage tolerance, where 1e6 = 100%
    uint256 public slippage;
    /// @notice TWAP duration in seconds, used to check `slippage`
    uint32 public twapDuration = 300;

    address[] public rewardAssets;

    constructor(
        address farmDispatcherAddress_,
        address swapStrategy_,
        address router_,
        address routerStatic_,
        address oracle_,
        address market_,
        address farmAsset_,
        uint256 slippage_,
        address rewardsAddress_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_
    )
        FarmDropStrategy(farmAsset_, farmDispatcherAddress_, rewardsAddress_, swapStrategy_)
        SkimStrategy(nonSkimAssets_)
    {
        router = IPAllActionV3(router_);
        routerStatic = IPRouterStatic(routerStatic_);
        oracle = IPPYLpOracle(oracle_);
        market = IPMarket(market_);
        (SY, PT, YT) = IPMarket(market).readTokens();
        rewardAssets = rewardAssets_;
        slippage = slippage_;
        SY_DECIMALS = SY.decimals();

        _validateTwapDuration(twapDuration);
    }

    /// @notice Sets the reward tokens to be recognised
    /// @param rewardAssets_ Token addresses
    function setRewardAssets(address[] memory rewardAssets_) external override onlyOwner {
        emit SetRewardAssets(rewardAssets, rewardAssets_);
        rewardAssets = rewardAssets_;
    }

    /// @notice Set the twap duration
    /// @param twapDuration_ New duration in seconds
    function setTwapDuration(uint32 twapDuration_) external override onlyOwner {
        _validateTwapDuration(twapDuration_);
        emit SetTwapDuration(twapDuration, twapDuration_);
        twapDuration = twapDuration_;
    }

    /// @notice Swap assets to borrow asset
    /// @param assets Array of assets to swap
    function _emergencySwap(address[] calldata assets) internal override {
        for (uint256 i; i < assets.length; ++i) {
            _swap(assets[i], asset, type(uint256).max);
        }
    }

    /// @notice Internal reusable function
    function _recogniseRewardsInBase() internal override {
        SY.claimRewards(address(this));
        YT.redeemDueInterestAndRewards(address(this), true, true);
        market.redeemRewards(address(this));

        /// @dev YT interest is in SY
        uint256 syBalance = SY.balanceOf(address(this));
        if (syBalance > 0) {
            SY.redeem(address(this), syBalance, farmAsset, 0, false);
        }

        for (uint256 i; i < rewardAssets.length; ++i) {
            _swap(rewardAssets[i], asset, type(uint256).max);
        }
        // Update drop percentage
        super._recogniseRewardsInBase();
    }

    /// @notice Swap between different assets
    /// @param inputAsset Input asset address
    /// @param outputAsset Output asset address
    /// @param amount Amount to swap
    function _swap(address inputAsset, address outputAsset, uint256 amount) internal returns (uint256) {
        if (inputAsset != outputAsset) {
            if (amount == type(uint256).max) {
                amount = IERC20(inputAsset).balanceOf(address(this));
            }

            if (amount > 0) {
                TransferHelper.safeApprove(inputAsset, address(swapStrategy), amount);
                amount = swapStrategy.swapInBase(inputAsset, outputAsset, amount);
            }
        }

        return amount;
    }

    function _validateTwapDuration(uint32 twapDuration_) internal view {
        // Make sure the oracle has enough TWAP data
        (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied) = oracle
            .getOracleState(address(market), twapDuration_);
        if (increaseCardinalityRequired) {
            // Oracle requires cardinality increase
            revert PFS_ORACLE_CARDINALITY(cardinalityRequired);
        }
        if (!oldestObservationSatisfied) {
            // Wait at least TWAP_DURATION seconds to populate observations
            revert PFS_ORACLE_UNPOPULATED();
        }
    }

    function _emptyLimit() internal pure returns (LimitOrderData memory) {}

    function _emptySwap() internal pure returns (SwapData memory) {}

    function _emptyApproxParams() internal pure returns (ApproxParams memory) {
        return ApproxParams(0, type(uint256).max, 0, 256, 1e14);
    }

    function _createTokenInputStruct(uint256 amountIn) internal view returns (TokenInput memory) {
        return
            TokenInput({
                tokenIn: farmAsset,
                netTokenIn: amountIn,
                tokenMintSy: farmAsset,
                pendleSwap: address(0),
                swapData: _emptySwap()
            });
    }

    function _emptyTokenOutputStruct() internal view returns (TokenOutput memory) {
        return
            TokenOutput({
                tokenOut: farmAsset,
                minTokenOut: 0,
                tokenRedeemSy: farmAsset,
                pendleSwap: address(0),
                swapData: _emptySwap()
            });
    }

    /// @notice Validate the difference for input and output value for market operations is within our tolerance
    function _validateRate(uint256 input, uint256 output) internal view {
        if (input - ((input * slippage) / SLIPPAGE_BASE) > output) {
            revert PFS_SLIPPAGE(input, output);
        }
    }
}
