// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./StrategyGenericPool.sol";
import "../../../../interfaces/external/strategy/farming/Curve/ICurve4.sol";

/**
 * @title StrategyMetaPool Contract
 * @dev Pool contract for farming strategies
 * @dev Overrides internal logic to handle Curve meta pool
 * @author Altitude Labs
 **/

contract StrategyMetaPool is StrategyGenericPool {
    constructor(
        address farmDispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        IConvexFarmStrategy.Config memory config
    ) StrategyGenericPool(farmDispatcherAddress, rewardsAddress, rewardAssets_, config) {}

    /// @notice Used to deposit into Curve pool
    /// @param toDeposit The amount of tokens to deposit
    function _curveDeposit(uint256 toDeposit, uint256 minLPOut) internal override {
        uint256[4] memory depositAmounts;
        depositAmounts[assetIndex] = toDeposit;

        TransferHelper.safeApprove(farmAsset, zapPool, toDeposit);
        ICurve4(zapPool).add_liquidity(depositAmounts, minLPOut);
    }

    /// @notice How much farm asset we would receive when redeeming LP tokens
    /// @param amount Amount of LP token
    /// @return amount The amount of the farm asset
    function _underlyingFromLP(uint256 amount) internal view override returns (uint256) {
        return ICurve(zapPool).calc_withdraw_one_coin(amount, int128(assetIndex));
    }

    /// @dev Used to withdraw from Curve pool
    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveWithdraw(uint256 lpAmount, uint256 minAssetOut) internal override {
        if (lpAmount > 0) {
            TransferHelper.safeApprove(address(curveLP), zapPool, lpAmount);
            ICurve(zapPool).remove_liquidity_one_coin(lpAmount, int128(assetIndex), minAssetOut);
        }
    }

    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveEmergencyWithdraw(uint256 lpAmount) internal virtual override {
        if (lpAmount > 0) {
            TransferHelper.safeApprove(address(curveLP), zapPool, lpAmount);
            ICurve4(zapPool).remove_liquidity(lpAmount, [uint256(0), 0, 0, 0]);
        }
    }
}
