pragma solidity 0.8.28;

import "./PendlePTStrategy.t.sol";
import "@pendle/core-v2/contracts/interfaces/IPMarket.sol";

contract PendlePTStrategyRebasing is PendlePTStrategy {
    function _setUp() internal override {
        // pendle_Market_aUSDC_Jun_25 must exist
        vm.rollFork(22463000);

        IPMarket(Constants.pendle_Market_aUSDC_Jun_25).increaseObservationsCardinalityNext(29);

        DEPOSIT = 1000e6;
        // TODO this is higher than it should be because there are checks on cumulative withdraws
        FEE_TOLERANCE = 20e15; // 2% (swap fee + volatility overdraw) acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.USDC);
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
            Constants.pendle_Market_aUSDC_Jun_25,
            address(farmAsset),
            5000, // 0.5%
            dispatcher,
            rewardAssets,
            nonSkimableAssets
        );

        farmStrategy = pendleStrategy;
    }
}
