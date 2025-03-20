// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../../../interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";

import "../FarmDropStrategy.sol";
import "../../../../libraries/utils/Utils.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";

/**
 * @title StrategyGenericPool Contract
 * @dev Base contract for Convex farming strategies
 *   - Deposit into Curve and then Convex protocols
 *   - Withdraw from Convex and then Curve protocols
 *   - Withdraw all from Convex and then Curve protocols
 * @author Altitude Labs
 **/

abstract contract StrategyGenericPool is FarmDropStrategy, IConvexFarmStrategy {
    /// @notice Curve pool address
    address public immutable override curvePool;
    /// @notice Curve LP token for the pool
    IERC20Metadata public immutable override curveLP;
    /// @notice Decimals for the Curve LP Token
    uint256 public immutable override crvDecimals;
    /// @notice Helper "zap" contract for this pool
    address public immutable override zapPool;
    /// @notice Convex booster address used to deposit the Curve LP token
    IConvex public immutable override convex;
    /// @notice Convex pool ID where we will deposit the Curve LP token
    uint256 public immutable override convexPoolID;
    /// @notice Convex (CVX) token address
    IERC20 public immutable override cvx;
    /// @notice Curve (CRV) token address
    IERC20 public immutable override crv;
    /// @notice Convex contract for rewards distribution
    ICVXRewards public immutable override crvRewards;
    /// @notice Index in the Curve pool of the token we are depositing
    uint128 public immutable override assetIndex;
    /// @notice Decimals of the token we are farming with
    uint8 public immutable override farmAssetDecimals;
    /// @notice Should we claim the extra rewards from Convex
    bool public override toClaimExtra;
    // Slippage, where 1e6 = 100%
    uint256 public constant override SLIPPAGE_BASE = 1_000_000;
    uint256 public override slippage;
    /// @notice Governance set amount, used to price the LP tokens
    /// @dev Used in place of get_virtual_price(), 18 decimals
    uint256 public override referencePrice;

    constructor(
        address farmDispatcherAddress,
        address rewardsAddress,
        IConvexFarmStrategy.Config memory config
    ) FarmDropStrategy(config.farmAsset, farmDispatcherAddress, rewardsAddress, config.swapStrategy) {
        if (config.slippage > SLIPPAGE_BASE || config.referencePrice == 0) {
            revert CFS_OUT_OF_BOUNDS();
        }

        curvePool = config.curvePool;
        curveLP = IERC20Metadata(config.curveLP);
        zapPool = config.zapPool;
        convex = IConvex(config.convex);
        cvx = IERC20(config.cvx);
        crv = IERC20(config.crv);
        crvRewards = ICVXRewards(config.crvRewards);
        crvDecimals = 10**curveLP.decimals();
        convexPoolID = config.convexPoolID;
        assetIndex = config.assetIndex;
        toClaimExtra = true;
        slippage = config.slippage;
        referencePrice = config.referencePrice;
        farmAssetDecimals = IERC20Metadata(config.farmAsset).decimals();
    }

    /// @notice Set the acceptable slippage for pool swaps
    function setSlippage(uint256 slippage_) external override onlyOwner {
        if (slippage_ > SLIPPAGE_BASE) {
            revert CFS_OUT_OF_BOUNDS();
        }
        emit SetSlippage(slippage, slippage_);
        slippage = slippage_;
    }

    /// @notice Set the reference price for pool tokens
    function setReferencePrice(uint256 price_) external override onlyOwner {
        if (price_ == 0) {
            revert CFS_OUT_OF_BOUNDS();
        }
        emit SetReferencePrice(referencePrice, price_);
        referencePrice = price_;
    }

    /// @notice Set toClaimExtra variable to enable/disable Convex extra rewards claiming
    /// @param toClaim_ To be claimable or not
    /// @dev Extra reward tokens can change and potentially misbehave, so we need a way to avoid them.
    function setToClaimExtraRewards(bool toClaim_) external override onlyOwner {
        toClaimExtra = toClaim_;
        emit SetToClaimExtraRewards(toClaim_);
    }

    /// @notice internal function to deposit everything into Curve & Convex
    function _deposit(uint256 amount) internal override {
        amount = _swap(asset, farmAsset, amount);
        _curveDeposit(amount, calcLPExpected(amount));

        // Deposit into Convex
        TransferHelper.safeApprove(address(curveLP), address(convex), curveLP.balanceOf(address(this)));
        convex.depositAll(convexPoolID, true);
    }

    /// @notice Internal function to withdraw from Curve & Convex
    function _withdraw(uint256 amount) internal override {
        // Check how much we have
        uint256 crvAmount = _calcExactLP(amount);
        uint256 farmBalance = crvRewards.balanceOf(address(this));
        if (crvAmount > farmBalance) {
            if (farmBalance > 0) {
                crvRewards.withdrawAll(false);
                convex.withdrawAll(convexPoolID);
            }
        } else {
            // Else withdraw the requested amount
            if (farmBalance > 0) {
                crvRewards.withdraw(crvAmount, false);
                convex.withdraw(convexPoolID, crvAmount);
            }
        }

        // Withdraw from Curve
        uint256 lpAmount = curveLP.balanceOf(address(this));
        if (lpAmount > 0) {
            _curveWithdraw(lpAmount, calcUnderlyingExpected(lpAmount));
            _swap(farmAsset, asset, type(uint256).max);
        }
    }

    /// @notice Return farm asset ammount specific for the farm provider
    function _getFarmAssetAmount() internal view virtual override returns (uint256 farmAssetAmount) {
        uint256 crvAmount = crvRewards.balanceOf(address(this));
        if (crvAmount > 0) {
            farmAssetAmount = _underlyingFromLP(crvAmount);
        }
    }

    /// @notice Calculate LP tokens required to receive `requestedAmount` borrow asset
    /// @param requestedAmount Amount of borrow asset to receive
    /// @return crvAmount Amount of LP tokens to be provided
    function _calcExactLP(uint256 requestedAmount) internal view virtual returns (uint256) {
        if (farmAsset != asset) {
            // If a conversion is happening, we substitute the requested sum with the
            // input amount we'd need to provide to get it in a swap
            requestedAmount = swapStrategy.getAmountIn(farmAsset, asset, requestedAmount);
        }

        // Get the amount of LP tokens we have
        uint256 maxLP = crvRewards.balanceOf(address(this));
        if (maxLP == 0) {
            return 0;
        }

        // Get the amount of farm asset we have
        uint256 maxAsset = _underlyingFromLP(maxLP);

        // If we have less than the amount requested, return the amount requested in LP tokens
        if (maxAsset < requestedAmount) {
            return maxLP + 1;
        }

        // Calculate the amount of LP tokens we need to withdraw
        uint256 lpAmount = (maxLP * requestedAmount) / maxAsset;
        uint256 maxLPReversed = (lpAmount * maxAsset) / requestedAmount;

        return lpAmount + (maxLP - maxLPReversed);
    }

    /**
     * @notice Calculate the minimum expected LP amount from providing liquidity
     * @param inputAmount_ Swap amount of inbound asset
     * @return minAmount Minimum expected amount of outbound asset
     */
    function calcLPExpected(uint256 inputAmount_) internal view returns (uint256 minAmount) {
        if (slippage == SLIPPAGE_BASE || inputAmount_ == 0) {
            return 0;
        }
        // referencePrice and LP tokens work with 18 decimals
        minAmount = Utils.scaleAmount(inputAmount_, farmAssetDecimals, 36) / referencePrice;

        minAmount = minAmount - ((minAmount * slippage) / SLIPPAGE_BASE);
    }

    /**
     * @notice Calculate the minimum expected asset amount from redeeming LP tokens
     * @param inputAmount_ Swap amount of inbound asset
     * @return minAmount Minimum expected amount of outbound asset
     */
    function calcUnderlyingExpected(uint256 inputAmount_) internal view returns (uint256 minAmount) {
        if (slippage == SLIPPAGE_BASE || inputAmount_ == 0) {
            return 0;
        }

        // referencePrice and LP tokens work with 18 decimals
        uint256 scaledAmount = Utils.scaleAmount(inputAmount_ * referencePrice, 36, farmAssetDecimals);

        minAmount = scaledAmount - ((scaledAmount * slippage) / SLIPPAGE_BASE);

        // Handle the case of having so small amount so the slippage can not be accounted for
        if (scaledAmount == minAmount && minAmount > 0 && slippage > 0) {
            minAmount -= 1;
        }
    }

    /// @notice Internal reusable function
    function _recogniseRewardsInBase() internal override {
        // Calculate and transfer the rewards from the convex pool
        crvRewards.getReward(address(this), toClaimExtra);

        // Swap all crv reward tokens to the asset
        uint256 amount = crv.balanceOf(address(this));
        if (amount > 0) {
            // Approve and swap
            TransferHelper.safeApprove(address(crv), address(swapStrategy), amount);
            swapStrategy.swapInBase(address(crv), asset, amount);
        }

        // Swap all cvx reward tokens to the asset
        amount = cvx.balanceOf(address(this));
        if (amount > 0) {
            TransferHelper.safeApprove(address(cvx), address(swapStrategy), amount);

            swapStrategy.swapInBase(address(cvx), asset, amount);
        }

        // If needed, loop over other reward tokens and swap to the asset
        if (toClaimExtra) {
            uint256 length = crvRewards.extraRewardsLength();
            for (uint256 i; i < length; ++i) {
                address extra = ICVXRewards(crvRewards.extraRewards(i)).rewardToken();

                amount = IERC20(extra).balanceOf(address(this));
                if (amount > 0) {
                    TransferHelper.safeApprove(extra, address(swapStrategy), amount);

                    swapStrategy.swapInBase(address(extra), asset, amount);
                }
            }
        }

        // Update drop percentage
        super._recogniseRewardsInBase();
    }

    /// @notice Withdraw all from Convex and then Curve
    function _emergencyWithdraw() internal override {
        // Reverts if we try to withdraw 0
        if (crvRewards.balanceOf(address(this)) > 0) {
            crvRewards.withdrawAll(false);
            convex.withdrawAll(convexPoolID);
            _curveEmergencyWithdraw(curveLP.balanceOf(address(this)));
        }
    }

    /// @notice Swap assets to borrow asset
    /// @param assets Array of assets to swap
    function _emergencySwap(address[] calldata assets) internal override {
        for (uint256 i; i < assets.length; ++i) {
            _swap(assets[i], asset, type(uint256).max);
        }
    }

    /// @notice Swap between different assets
    function _swap(
        address inputAsset,
        address outputAsset,
        uint256 amount
    ) internal returns (uint256) {
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

    /// @notice Handles farm deposit
    function _curveDeposit(uint256 toDeposit, uint256 minLPOut) internal virtual;

    /// @notice How much farm asset we would receive when redeeming LP tokens
    function _underlyingFromLP(uint256 amount) internal view virtual returns (uint256);

    /// @notice Handles farm withdrawal
    function _curveWithdraw(uint256 balance, uint256 minAssetOut) internal virtual;

    /// @notice Handles farm balanced withdrawal
    function _curveEmergencyWithdraw(uint256 balance) internal virtual;
}
