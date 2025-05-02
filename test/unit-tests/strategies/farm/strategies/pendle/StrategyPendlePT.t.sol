pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {IToken} from "../../../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";
import {StrategyPendlePT} from "../../../../../../contracts/strategies/farming/strategies/pendle/StrategyPendlePT.sol";
import {ISwapStrategy} from "../../../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import "../../../../../../contracts/interfaces/internal/strategy/ISkimStrategy.sol";
import {FarmStrategyUnitTest} from "../FarmStrategyUnitTest.sol";
import "../../../../../../contracts/interfaces/internal/strategy/farming/IPendleFarmStrategy.sol";

// Mocks
import {RouterMock, OracleMock, MarketMock, RouterStaticMock} from "../../../../../mocks/PendleMock.sol";
import "@pendle/core-v2/contracts/interfaces/IPMarket.sol";

contract StrategyPendlePTTest is FarmStrategyUnitTest {
    using stdStorage for StdStorage;

    address public router;
    address public routerStatic;
    address public oracle;
    MarketMock public market;
    address public rewardAsset;

    function _setUp() internal override {
        rewardAsset = BaseGetter.getBaseERC20(18);
        router = address(new RouterMock(asset));
        routerStatic = address(new RouterStaticMock(asset));
        oracle = address(new OracleMock(asset));
        market = new MarketMock(
            asset,
            BaseGetter.getBaseERC20(18),
            BaseGetter.getBaseERC20(18),
            BaseGetter.getBaseERC20(18)
        );

        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = rewardAsset;

        address[] memory nonSkimableAssets = new address[](2);
        nonSkimableAssets[0] = asset;
        nonSkimableAssets[1] = rewardAsset;

        farmStrategy = new StrategyPendlePT(
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            router,
            routerStatic,
            oracle,
            address(market),
            asset,
            0,
            address(this),
            rewardAssets,
            nonSkimableAssets
        );
    }

    function test_CorrectInitialization() public view {
        StrategyPendlePT strategy = StrategyPendlePT(address(farmStrategy));

        assertEq(address(strategy.router()), address(router));
        assertEq(address(strategy.market()), address(market));
        assertEq(address(strategy.oracle()), address(oracle));
        assertEq(strategy.rewardAssets(0), rewardAsset);
    }

    function test_SetRewardsAsset() public {
        StrategyPendlePT strategy = StrategyPendlePT(address(farmStrategy));

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = BaseGetter.getBaseERC20(18);
        rewardAssets[1] = BaseGetter.getBaseERC20(18);

        strategy.setRewardAssets(rewardAssets);
        assertEq(strategy.rewardAssets(0), rewardAssets[0]);
        assertEq(strategy.rewardAssets(1), rewardAssets[1]);
    }

    function test_NonOwnerSetsRewardsAsset() public {
        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = BaseGetter.getBaseERC20(18);

        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        StrategyPendlePT(address(farmStrategy)).setRewardAssets(rewardAssets);
    }

    function test_SetSlippage() public {
        StrategyPendlePT strategy = StrategyPendlePT(address(farmStrategy));
        uint256 newSlippage = 5000; // 0.5%

        strategy.setSlippage(newSlippage);
        assertEq(strategy.slippage(), newSlippage);
    }

    function test_SetSlippageExceedsBase() public {
        StrategyPendlePT strategy = StrategyPendlePT(address(farmStrategy));
        uint256 invalidSlippage = strategy.SLIPPAGE_BASE() + 1;

        vm.expectRevert(
            abi.encodeWithSelector(IPendleFarmStrategy.PFS_SLIPPAGE.selector, strategy.slippage(), invalidSlippage)
        );
        strategy.setSlippage(invalidSlippage);
    }

    function test_NonOwnerSetsSlippage() public {
        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        StrategyPendlePT(address(farmStrategy)).setSlippage(5000);
    }

    function test_Skim() public {
        address[] memory skimAssets = new address[](1);
        skimAssets[0] = BaseGetter.getBaseERC20(18);

        IToken(skimAssets[0]).mint(address(farmStrategy), DEPOSIT);

        StrategyPendlePT(address(farmStrategy)).skim(skimAssets, address(this));

        assertEq(IToken(skimAssets[0]).balanceOf(address(this)), DEPOSIT);
    }

    function test_SkimNonSkimmable() public {
        address[] memory skimAssets = new address[](1);
        skimAssets[0] = rewardAsset;

        IToken(skimAssets[0]).mint(address(farmStrategy), DEPOSIT);

        vm.expectRevert(ISkimStrategy.SK_NON_SKIM_ASSET.selector);
        StrategyPendlePT(address(farmStrategy)).skim(skimAssets, address(this));
    }

    function test_NonOwnerSkims() public {
        address[] memory skimAssets = new address[](1);
        skimAssets[0] = BaseGetter.getBaseERC20(18);

        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        StrategyPendlePT(address(farmStrategy)).skim(skimAssets, address(this));
    }

    function test_RewardsRecognition() public {
        IToken(rewardAsset).mint(address(farmStrategy), DEPOSIT);

        vm.mockCall(address(market.SY()), abi.encodeWithSignature("claimRewards(address)"), abi.encode([0]));
        vm.mockCall(
            address(market.YT()),
            abi.encodeWithSignature("redeemDueInterestAndRewards(address,bool,bool)"),
            abi.encode(0, [0])
        );

        vm.mockCall(address(market), abi.encodeWithSignature("redeemRewards(address)"), abi.encode([0]));

        farmStrategy.recogniseRewardsInBase();

        vm.clearMockedCalls();

        assertEq(IToken(asset).balanceOf(address(this)), DEPOSIT);
    }

    function test_RewardsRecognitionSwapFails() public {
        IToken(rewardAsset).mint(address(farmStrategy), DEPOSIT);
        vm.mockCall(address(market.SY()), abi.encodeWithSignature("claimRewards(address)"), abi.encode([0]));
        vm.mockCall(
            address(market.YT()),
            abi.encodeWithSignature("redeemDueInterestAndRewards(address,bool,bool)"),
            abi.encode(0, [0])
        );
        vm.mockCall(address(market), abi.encodeWithSignature("redeemRewards(address)"), abi.encode([0]));

        vm.mockCallRevert(
            address(farmStrategy.swapStrategy()),
            abi.encodeWithSelector(ISwapStrategy.swapInBase.selector, rewardAsset, asset, DEPOSIT),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        vm.expectRevert("SWAP_STRATEGY_SWAP_NOT_PROCEEDED");
        farmStrategy.recogniseRewardsInBase();
        vm.clearMockedCalls();
    }

    function _assertDeposit() internal view override {
        assertEq(market.PT().balanceOf(address(farmStrategy)), DEPOSIT);
    }

    function _changeFarmAsset() internal override returns (address newFarmAsset) {
        newFarmAsset = BaseGetter.getBaseERC20(18);
        // Update storage to enforce swap
        stdstore.target(address(farmStrategy)).sig("farmAsset()").checked_write(newFarmAsset);

        stdstore.target(address(market)).sig("asset()").checked_write(newFarmAsset);
    }
}
