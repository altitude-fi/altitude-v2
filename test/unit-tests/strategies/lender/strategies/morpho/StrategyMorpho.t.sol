pragma solidity 0.8.28;

import "../../LenderStrategyUnitTest.sol";
import {Constants} from "../../../../../../scripts/deployer/Constants.sol";
import "../../../../../../contracts/strategies/lending/morpho/StrategyMorphoV1.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";
import {UtilsLib} from "@morpho-org/morpho-blue/src/libraries/UtilsLib.sol";
import {WAD} from "@morpho-org/morpho-blue/src/libraries/MathLib.sol";

contract MorphoStrategy is LenderStrategyUnitTest {
    StrategyMorphoV1 public morphoStrategy;
    IMorpho public morpho;

    function _setUp() internal override {
        vault = makeAddr("Vault");
        borrowAsset = IERC20Metadata(Constants.USDC);
        supplyAsset = IERC20Metadata(Constants.wstETH);
        morpho = IMorpho(Constants.morpho_Pool);

        morphoStrategy = new StrategyMorphoV1(
            vault,
            address(supplyAsset),
            address(borrowAsset),
            Constants.morpho_Pool,
            Id.wrap(Constants.morpho_Market_WSTETH_USDC),
            MAX_DEPOSIT_FEE,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            vault,
            new address[](0)
        );

        DEPOSIT = 10e18;
        BORROW = (_priceSupplyInBorrow(DEPOSIT) * 50) / 100; // 50% of the supply value
    }

    function _priceSupplyInBorrow(uint256 amount) internal view returns (uint256) {
        uint256 price = IOracle(morphoStrategy.marketOracle()).price();
        assertNotEq(price, 0);

        uint8 oraclePriceDecimals = 36 + borrowAsset.decimals() - supplyAsset.decimals();

        price = Utils.scaleAmount(price, oraclePriceDecimals, IERC20Metadata(borrowAsset).decimals());

        return (amount * price) / 10**supplyAsset.decimals();
    }

    function test_paidLiquidationFee() public view {
        uint256 liquidationIncentiveFactor = UtilsLib.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR,
            MathLib.wDivDown(WAD, WAD - MathLib.wMulDown(LIQUIDATION_CURSOR, WAD - morphoStrategy.marketLltv()))
        );
        assertNotEq(liquidationIncentiveFactor, 0);
        uint256 supplyLoss = 10e18;
        assertEq(
            morphoStrategy.paidLiquidationFee(supplyLoss),
            supplyLoss - ((supplyLoss * WAD) / liquidationIncentiveFactor)
        );
    }

    function test_setRewardAssets() public {
        address[] memory rewardsList = new address[](2);
        rewardsList[0] = makeAddr("token1");
        rewardsList[1] = makeAddr("token2");
        morphoStrategy.setRewardAssets(rewardsList);
        assertEq(morphoStrategy.rewardAssets(0), rewardsList[0]);
        assertEq(morphoStrategy.rewardAssets(1), rewardsList[1]);
    }

    function test_skimTransferTokens() public {
        address[] memory assets = new address[](2);
        assets[0] = BaseGetter.getBaseERC20(18);
        assets[1] = BaseGetter.getBaseERC20(18);

        mintToken(assets[0], address(morphoStrategy), 100 * 10**18);
        mintToken(assets[1], address(morphoStrategy), 200 * 10**18);

        address receiver = makeAddr("skimReceiver");
        morphoStrategy.skim(assets, receiver);

        assertEq(IERC20Metadata(assets[0]).balanceOf(receiver), 100 * 10**18);
        assertEq(IERC20Metadata(assets[1]).balanceOf(receiver), 200 * 10**18);
    }

    function test_skimNonOwner() public {
        address[] memory assets = new address[](0);
        vm.startPrank(makeAddr("non-owner"));
        vm.expectRevert("Ownable: caller is not the owner");
        morphoStrategy.skim(assets, address(0));
        vm.stopPrank();
    }

    function test_invalidGetInBase() public {
        vm.expectRevert(ILenderStrategy.LS_INVALID_ASSET_PAIR.selector);
        morphoStrategy.getInBase(address(1), address(borrowAsset));

        vm.expectRevert(ILenderStrategy.LS_INVALID_ASSET_PAIR.selector);
        morphoStrategy.getInBase(address(supplyAsset), address(1));

        vm.expectRevert(ILenderStrategy.LS_INVALID_ASSET_PAIR.selector);
        morphoStrategy.getInBase(address(borrowAsset), address(borrowAsset));

        vm.expectRevert(ILenderStrategy.LS_INVALID_ASSET_PAIR.selector);
        morphoStrategy.getInBase(address(supplyAsset), address(supplyAsset));
    }

    function test_getInBaseReverse() public view {
        assertApproxEqRel(
            (10**borrowAsset.decimals() * 10**supplyAsset.decimals()) /
                _priceSupplyInBorrow(10**supplyAsset.decimals()),
            morphoStrategy.getInBase(address(borrowAsset), address(supplyAsset)),
            0.005e18
        );
    }

    function test_getLendingPool() public view {
        assertEq(morphoStrategy.getLendingPool(), Constants.morpho_Pool);
    }
}
