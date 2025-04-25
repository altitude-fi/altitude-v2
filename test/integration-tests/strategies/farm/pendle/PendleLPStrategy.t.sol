// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../FarmStrategyIntegrationTest.sol";
import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {StrategyPendleLP} from "../../../../../contracts/strategies/farming/strategies/pendle/StrategyPendleLP.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";

import "../../../../../contracts/interfaces/internal/strategy/farming/IPendleFarmStrategy.sol";

contract PendleLPStrategy is FarmStrategyIntegrationTest {
    IPendleFarmStrategy public pendleStrategy;

    function _setUp() internal override {
        // pendle_Market_SUSDE_Mar_25 must exist
        vm.rollFork(21261000);

        DEPOSIT = 1000e6;
        // TODO this is higher than it should be because there are checks on cumulative withdraws
        FEE_TOLERANCE = 20e15; // 2% (swap fee + volatility overdraw) acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.sUSDe);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = Constants.pendle_Token;
        rewardAssets[1] = Constants.sUSDe;

        address[] memory nonSkimableAssets = new address[](3);
        nonSkimableAssets[0] = address(asset);
        nonSkimableAssets[1] = Constants.pendle_Token;
        nonSkimableAssets[2] = Constants.sUSDe;

        pendleStrategy = new StrategyPendleLP(
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            Constants.pendle_Router,
            Constants.pendle_RouterStatic,
            Constants.pendle_Oracle,
            Constants.pendle_Market_SUSDE_Mar_25,
            address(farmAsset),
            6000, // 0.6%
            dispatcher,
            rewardAssets,
            nonSkimableAssets
        );

        farmStrategy = pendleStrategy;
    }

    function _accumulateRewards() internal virtual override returns (address[] memory) {
        mintToken(Constants.pendle_Token, address(farmStrategy), 100 * 10 ** IToken(Constants.pendle_Token).decimals());

        address[] memory rewards = new address[](1);
        rewards[0] = Constants.pendle_Token;
        return rewards;
    }

    function test_YtInterest() public virtual {
        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = Constants.sUSDe;
        pendleStrategy.setRewardAssets(rewardAssets);

        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 100);

        uint256 amountWithdrawn = asset.balanceOf(dispatcher);
        farmStrategy.recogniseRewardsInBase();
        amountWithdrawn = asset.balanceOf(dispatcher) - amountWithdrawn;
        vm.stopPrank();

        assertTrue(amountWithdrawn > 0, "Zero interest");
    }
}
