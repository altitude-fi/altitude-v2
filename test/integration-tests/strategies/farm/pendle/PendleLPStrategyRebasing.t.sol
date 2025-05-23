pragma solidity 0.8.28;

import "./PendleLPStrategy.t.sol";

contract PendleLPStrategyRebasing is PendleLPStrategy {
    function _setUp() internal override {
        // pendle_Market_aUSDC_Jun_25 must exist
        vm.rollFork(22463670);

        // Let the oracle accomodate the twap for this pool
        IPMarket(Constants.pendle_Market_aUSDC_Jun_25).increaseObservationsCardinalityNext(165);
        skip(1800);

        DEPOSIT = 1000e6;
        // TODO this is higher than it should be because there are checks on cumulative withdraws
        FEE_TOLERANCE = 20e15; // 2% (swap fee + volatility overdraw) acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.USDC);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = Constants.pendle_Token;
        rewardAssets[1] = Constants.USDC;

        address[] memory nonSkimableAssets = new address[](3);
        nonSkimableAssets[0] = address(asset);
        nonSkimableAssets[1] = Constants.pendle_Token;
        nonSkimableAssets[2] = Constants.USDC;

        pendleStrategy = new StrategyPendleLP(
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            Constants.pendle_Router,
            Constants.pendle_RouterStatic,
            Constants.pendle_Oracle,
            Constants.pendle_Market_aUSDC_Jun_25,
            address(farmAsset),
            50000, // 5%, TODO YT has very high slippage
            dispatcher,
            rewardAssets,
            nonSkimableAssets
        );

        farmStrategy = pendleStrategy;
    }

    function test_YtInterest() public override {
        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = Constants.USDC;
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

        assertGt(amountWithdrawn, 0, "Zero interest");
    }
}
