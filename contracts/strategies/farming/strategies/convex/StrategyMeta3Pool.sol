// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./StrategyGenericPool.sol";
import "../../../../interfaces/external/strategy/farming/Curve/I3PoolZap.sol";

/**
 * @title StrategyMeta3Pool Contract
 * @dev 3 Pool contract for farming strategies
 * @dev Overrides internal logic to handle Curve meta 3 pool
 * @author Altitude Labs
 **/

contract StrategyMeta3Pool is StrategyGenericPool {
    constructor(
        address farmDispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        IConvexFarmStrategy.Config memory config
    ) StrategyGenericPool(farmDispatcherAddress, rewardsAddress, rewardAssets_, config) {}

    /// @notice Used to deposit into Curve meta 3 pool
    /// @param toDeposit The amount of tokens to deposit
    function _curveDeposit(uint256 toDeposit, uint256 minLPOut) internal override {
        uint256[4] memory depositAmounts;
        depositAmounts[assetIndex] = toDeposit;

        TransferHelper.safeApprove(farmAsset, zapPool, toDeposit);
        I3PoolZap(zapPool).add_liquidity(curvePool, depositAmounts, minLPOut);
    }

    /// @notice How much farm asset we would receive when redeeming LP tokens
    /// @param amount Amount of LP token
    /// @return amount The amount of the farm asset
    function _underlyingFromLP(uint256 amount) internal view override returns (uint256) {
        return I3PoolZap(zapPool).calc_withdraw_one_coin(curvePool, amount, int128(assetIndex));
    }

    /// @notice Used to withdraw from Curve meta 3 pool
    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveWithdraw(uint256 lpAmount, uint256 minAssetOut) internal override {
        if (lpAmount > 0) {
            TransferHelper.safeApprove(address(curveLP), zapPool, lpAmount);

            I3PoolZap(zapPool).remove_liquidity_one_coin(curvePool, lpAmount, int128(assetIndex), minAssetOut);
        }
    }

    /// @param lpAmount The amount of Curve LP tokens based on which to withdraw
    function _curveEmergencyWithdraw(uint256 lpAmount) internal virtual override {
        if (lpAmount > 0) {
            TransferHelper.safeApprove(address(curveLP), zapPool, lpAmount);
            I3PoolZap(zapPool).remove_liquidity(curvePool, lpAmount, [uint256(0), 0, 0, 0]);
        }
    }
}
