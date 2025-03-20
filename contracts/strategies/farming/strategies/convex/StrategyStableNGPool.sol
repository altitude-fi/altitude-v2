// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./StrategyGenericPool.sol";
import "../../../../interfaces/external/strategy/farming/Curve/ICurveNG.sol";

/**
 * @title StrategyStable2Pool Contract
 * @dev Pool contract for farming strategies
 * @dev Overrides internal logic to handle Curve stableswap pool
 * @author Altitude Labs
 **/

contract StrategyStableNGPool is StrategyGenericPool {
    constructor(
        address farmDispatcherAddress,
        address rewardsAddress,
        IConvexFarmStrategy.Config memory config
    ) StrategyGenericPool(farmDispatcherAddress, rewardsAddress, config) {}

    /// @notice Used to deposit into Curve pool
    /// @param toDeposit The amount of tokens to deposit
    function _curveDeposit(uint256 toDeposit, uint256 minLPOut) internal virtual override {
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[assetIndex] = toDeposit;

        TransferHelper.safeApprove(farmAsset, curvePool, toDeposit);
        ICurveNG(curvePool).add_liquidity(depositAmounts, minLPOut);
    }

    /// @notice How much farm asset we would receive when redeeming LP tokens
    /// @param amount Amount of LP token
    /// @return amount The amount of the farm asset
    function _underlyingFromLP(uint256 amount) internal view override returns (uint256) {
        return ICurveNG(curvePool).calc_withdraw_one_coin(amount, int128(assetIndex));
    }

    /// @dev Used to withdraw from Curve pool
    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveWithdraw(uint256 lpAmount, uint256 minAssetOut) internal virtual override {
        if (lpAmount > 0) {
            TransferHelper.safeApprove(address(curveLP), curvePool, lpAmount);
            ICurveNG(curvePool).remove_liquidity_one_coin(lpAmount, int128(assetIndex), minAssetOut);
        }
    }

    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveEmergencyWithdraw(uint256 lpAmount) internal virtual override {
        if (lpAmount > 0) {
            uint256[] memory minOutAmounts = new uint256[](2);

            TransferHelper.safeApprove(address(curveLP), curvePool, lpAmount);
            ICurveNG(curvePool).remove_liquidity(lpAmount, minOutAmounts);
        }
    }
}
