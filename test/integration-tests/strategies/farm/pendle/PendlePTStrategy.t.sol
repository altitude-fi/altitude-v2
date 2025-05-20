pragma solidity 0.8.28;

import "../FarmStrategyIntegrationTest.sol";
import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {StrategyPendlePT} from "../../../../../contracts/strategies/farming/strategies/pendle/StrategyPendlePT.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import "../../../../../contracts/interfaces/internal/strategy/farming/IPendleFarmStrategy.sol";

contract PendlePTStrategy is FarmStrategyIntegrationTest {
    IPendleFarmStrategy public pendleStrategy;

    function _setUp() internal virtual override {
        // pendle_Market_SUSDE_Mar_25 must exist
        vm.rollFork(21261000);

        DEPOSIT = 1000e6;
        // TODO this is higher than it should be because there are checks on cumulative withdraws
        FEE_TOLERANCE = 20e15; // 2% (swap fee + volatility overdraw) acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.sUSDe);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = Constants.pendle_Token;

        address[] memory nonSkimableAssets = new address[](2);
        nonSkimableAssets[0] = address(asset);
        nonSkimableAssets[1] = Constants.pendle_Token;

        pendleStrategy = new StrategyPendlePT(
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            Constants.pendle_Router,
            Constants.pendle_RouterStatic,
            Constants.pendle_Oracle,
            Constants.pendle_Market_SUSDE_Mar_25,
            address(farmAsset),
            5000, // 0.5%
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

    function test_PtRedeem() public virtual {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        vm.warp(pendleStrategy.market().expiry() + 1);
        vm.roll(block.number + 1000);

        uint256 amountWithdrawn = asset.balanceOf(dispatcher);
        farmStrategy.withdraw(DEPOSIT / 2);
        amountWithdrawn = asset.balanceOf(dispatcher) - amountWithdrawn;
        vm.stopPrank();

        // Since market is expired, we redeemed everything
        assertTrue(farmStrategy.balance() == 0, "Zero balance");

        uint256 withdrawnTolerance = DEPOSIT - (DEPOSIT * FEE_TOLERANCE) / MAX_FEE_TOLERANCE;

        assertTrue(amountWithdrawn >= withdrawnTolerance, "Fee tolerance");
    }
}
