// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../strategies/farming/strategies/convex/StrategyMeta3Pool.sol";

/**
 * @title Mock Contract for testing farm drop
 * @author Altitude Labs
 **/

contract TestFarmStrategy is StrategyMeta3Pool {
    constructor(
        address dispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        IConvexFarmStrategy.Config memory config
    ) StrategyMeta3Pool(dispatcherAddress, rewardsAddress, rewardAssets_, config) {}

    function testWithdraw(uint256 amount) external {
        uint256 crvAmount = _calcExactLP(amount);
        crvRewards.withdraw(crvAmount, false);
        convex.withdraw(convexPoolID, crvAmount);
        uint256 curveBalance = curveLP.balanceOf(address(this));
        _curveWithdraw(curveBalance, calcUnderlyingExpected(curveBalance));
        TransferHelper.safeTransfer(asset, msg.sender, IERC20(asset).balanceOf(address(this)));
    }

    function testDeposit(uint256 amount) external {
        // Transfer funds from vault
        TransferHelper.safeTransferFrom(asset, msg.sender, address(this), amount);
        _deposit(amount);
    }
}
