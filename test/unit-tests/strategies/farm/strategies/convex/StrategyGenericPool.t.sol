pragma solidity 0.8.28;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";

import {FarmStrategyUnitTest} from "../FarmStrategyUnitTest.sol";

import {IToken} from "../../../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";
import {TokensGenerator} from "../../../../../utils/TokensGenerator.sol";
import {BaseConvexStrategy} from "../../../../../base/BaseConvexStrategy.sol";
import {FarmDispatcher} from "../../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {ISwapStrategy} from "../../../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {IConvexFarmStrategy} from "../../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";

// Mocks
import {ConvexMock} from "../../../../../mocks/ConvexMock.sol";
import {CRVRewardsMock} from "../../../../../mocks/CRVRewardsMock.sol";

contract StrategyGenericPoolTest is FarmStrategyUnitTest, TokensGenerator {
    using stdStorage for StdStorage;

    IConvexFarmStrategy.Config public config;

    address public crvToken;
    address public cvxToken;
    address public curveLP;
    address public convex;
    address public crvRewards;

    function _setUp() internal override {
        crvToken = BaseGetter.getBaseERC20(18);
        cvxToken = BaseGetter.getBaseERC20(18);
        curveLP = BaseGetter.getBaseERC20(18);

        address[] memory rewards = new address[](2);
        rewards[0] = crvToken;
        rewards[1] = cvxToken;

        crvRewards = address(new CRVRewardsMock(curveLP, rewards));
        convex = address(new ConvexMock(curveLP, crvRewards));
        CRVRewardsMock(crvRewards).setConvex(convex);

        config = IConvexFarmStrategy.Config(
            address(0),
            curveLP,
            address(0),
            convex,
            0,
            cvxToken,
            crvToken,
            crvRewards,
            0,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            0,
            1e18,
            asset
        );

        // Rewards receiver = address(this)
        farmStrategy = new BaseConvexStrategy(dispatcher, address(this), config);
    }

    function test_CorrectInitialization() public view {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));
        assertEq(convexStrategy.curvePool(), config.curvePool);
        assertEq(address(convexStrategy.curveLP()), config.curveLP);
        assertEq(convexStrategy.zapPool(), config.zapPool);
        assertEq(address(convexStrategy.convex()), config.convex);
        assertEq(address(convexStrategy.cvx()), config.cvx);
        assertEq(address(convexStrategy.crv()), config.crv);
        assertEq(address(convexStrategy.crvRewards()), config.crvRewards);
        assertEq(convexStrategy.convexPoolID(), config.convexPoolID);
        assertEq(convexStrategy.assetIndex(), config.assetIndex);
        assertEq(convexStrategy.toClaimExtra(), true);
        assertEq(convexStrategy.referencePrice(), config.referencePrice);
    }

    function test_InitializationReverts() public {
        config.slippage = 1000001;
        vm.expectRevert(IConvexFarmStrategy.CFS_OUT_OF_BOUNDS.selector);
        farmStrategy = new BaseConvexStrategy(dispatcher, address(this), config);

        config.slippage = 1000000;
        config.referencePrice = 0;
        vm.expectRevert(IConvexFarmStrategy.CFS_OUT_OF_BOUNDS.selector);
        farmStrategy = new BaseConvexStrategy(dispatcher, address(this), config);
    }

    function test_DepositEntireLPBalance() public {
        // Mint directly by manipulating the internal storage
        mintToken(curveLP, address(farmStrategy), 100 * 10 ** IToken(curveLP).decimals());
        assertEq(IToken(curveLP).balanceOf(address(farmStrategy)), 100 * 10 ** IToken(curveLP).decimals());

        vm.startPrank(dispatcher);
        IToken(asset).mint(dispatcher, DEPOSIT);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        assertEq(IToken(curveLP).balanceOf(address(farmStrategy)), 0);
        assertTrue(farmStrategy.balance() > DEPOSIT);
    }

    function test_DisableSlippage() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));
        convexStrategy.setSlippage(convexStrategy.SLIPPAGE_BASE());

        vm.startPrank(dispatcher);
        IToken(asset).mint(dispatcher, DEPOSIT);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        // In case the slippage = 100% the minted curveLP tokens are expected to be 0
        assertEq(IToken(curveLP).balanceOf(address(crvRewards)), 0);
    }

    function test_SetExtraRewards() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));
        convexStrategy.setToClaimExtraRewards(true);
        assertEq(convexStrategy.toClaimExtra(), true);

        convexStrategy.setToClaimExtraRewards(false);
        assertEq(convexStrategy.toClaimExtra(), false);
    }

    function test_NonOwnerWhitelistExtraRewards() public {
        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        BaseConvexStrategy(address(farmStrategy)).setToClaimExtraRewards(false);
    }

    function test_SetSlippage() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        uint256 slippage = 1e5;
        convexStrategy.setSlippage(slippage);
        assertEq(convexStrategy.slippage(), slippage);

        slippage = 2e5;
        convexStrategy.setSlippage(slippage);
        assertEq(convexStrategy.slippage(), slippage);
    }

    function test_SetSlippageOutsideLimits() public {
        vm.expectRevert(IConvexFarmStrategy.CFS_OUT_OF_BOUNDS.selector);
        BaseConvexStrategy(address(farmStrategy)).setSlippage(1e7);
    }

    function test_NonOwnerSetSlippage() public {
        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        BaseConvexStrategy(address(farmStrategy)).setSlippage(1e5);
    }

    function test_SetReferencePrice() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        uint256 referencePrice = 1e18;
        convexStrategy.setReferencePrice(referencePrice);
        assertEq(convexStrategy.referencePrice(), referencePrice);

        referencePrice = 2e18;
        convexStrategy.setReferencePrice(referencePrice);
        assertEq(convexStrategy.referencePrice(), referencePrice);
    }

    function test_SetZeroReferencePrice() public {
        vm.expectRevert(IConvexFarmStrategy.CFS_OUT_OF_BOUNDS.selector);
        BaseConvexStrategy(address(farmStrategy)).setReferencePrice(0);
    }

    function test_NonOwnerSetReferencePrice() public {
        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        BaseConvexStrategy(address(farmStrategy)).setReferencePrice(1);
    }

    function test_CalcExactLPWithNoSwap() public {
        _calcExactLP();
    }

    function test_CalcExactLPWithSwap() public {
        _changeFarmAsset();
        _calcExactLP();
    }

    function _calcExactLP() internal {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        // No CRV Rewards balance
        assertEq(convexStrategy.exactLP(DEPOSIT), 0);

        IToken(curveLP).mint(crvRewards, DEPOSIT);

        // Request bigger amount
        assertEq(convexStrategy.exactLP(DEPOSIT * 2), DEPOSIT + 1);

        // Request smaller amount
        assertEq(convexStrategy.exactLP(DEPOSIT / 2), DEPOSIT / 2);
    }

    function test_CalcLPExpected() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        // With no slippage
        assertEq(convexStrategy.lpExpected(DEPOSIT), DEPOSIT);

        // With minor slippage
        convexStrategy.setSlippage(1e4); // 1% slippage
        assertEq(convexStrategy.lpExpected(DEPOSIT), DEPOSIT - DEPOSIT / 100);
    }

    function test_CalcLPExpectedWithMaxSlippageAndZeroAmount() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        assertEq(convexStrategy.lpExpected(0), 0);

        convexStrategy.setSlippage(convexStrategy.SLIPPAGE_BASE());
        assertEq(convexStrategy.lpExpected(0), 0);
    }

    function test_CalcUnderlyingExpected() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        // With no slippage
        assertEq(convexStrategy.underlyingExpected(DEPOSIT), DEPOSIT);

        // With minor slippage
        convexStrategy.setSlippage(1e4); // 1% slippage
        assertEq(convexStrategy.underlyingExpected(DEPOSIT), DEPOSIT - DEPOSIT / 100);

        // Amount for which the slippage can not be applied
        assertEq(convexStrategy.underlyingExpected(10), 9);
    }

    function test_CalcUnderlyingExpectedWithMaxSlippageAndZeroAmount() public {
        BaseConvexStrategy convexStrategy = BaseConvexStrategy(address(farmStrategy));

        assertEq(convexStrategy.underlyingExpected(0), 0);

        convexStrategy.setSlippage(convexStrategy.SLIPPAGE_BASE());
        assertEq(convexStrategy.underlyingExpected(0), 0);
    }

    function test_RewardsRecognitionWithZeroRewards() public {
        // Simulate zero rewards
        CRVRewardsMock(crvRewards).deactivateRewards();

        farmStrategy.recogniseRewardsInBase();

        assertEq(IToken(asset).balanceOf(address(this)), 0);
    }

    function test_RewardsRecognitionWithNoExtra() public {
        BaseConvexStrategy(address(farmStrategy)).setToClaimExtraRewards(false);
        farmStrategy.recogniseRewardsInBase();

        assertEq(
            IToken(asset).balanceOf(address(this)),
            CRVRewardsMock(crvRewards).getRewardRate(1) + CRVRewardsMock(crvRewards).getRewardRate(2)
        );
    }

    function test_RewardsRecognitionWithExtra() public {
        farmStrategy.recogniseRewardsInBase();

        assertEq(
            IToken(asset).balanceOf(address(this)),
            CRVRewardsMock(crvRewards).getRewardRate(0) +
                CRVRewardsMock(crvRewards).getRewardRate(1) +
                CRVRewardsMock(crvRewards).getRewardRate(2)
        );
    }

    function test_RewardsRecognitionSwapFails() public {
        vm.mockCallRevert(
            address(farmStrategy.swapStrategy()),
            abi.encodeWithSelector(
                ISwapStrategy.swapInBase.selector,
                crvToken,
                asset,
                CRVRewardsMock(crvRewards).getRewardRate(1)
            ),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        vm.expectRevert("SWAP_STRATEGY_SWAP_NOT_PROCEEDED");
        farmStrategy.recogniseRewardsInBase();
    }

    function _assertDeposit() internal view override {
        assertEq(IToken(asset).balanceOf(address(farmStrategy)), 0);
        assertEq(IToken(curveLP).balanceOf(address(farmStrategy)), 0);
        assertEq(IToken(curveLP).balanceOf(address(crvRewards)), DEPOSIT);
    }

    function _changeFarmAsset() internal override returns (address newFarmAsset) {
        newFarmAsset = BaseGetter.getBaseERC20(18);
        // Update storage to enforce swap
        stdstore.target(address(farmStrategy)).sig("farmAsset()").checked_write(newFarmAsset);
    }
}
