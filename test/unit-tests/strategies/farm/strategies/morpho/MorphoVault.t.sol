pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {IToken} from "../../../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";
import {MorphoVault} from "../../../../../../contracts/strategies/farming/strategies/morpho/MorphoVault.sol";
import {ISwapStrategy} from "../../../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {FarmStrategyUnitTest} from "../FarmStrategyUnitTest.sol";

// Mocks
import {MorphoMock} from "../../../../../mocks/MorphoMock.sol";

contract MorphoVaultTest is FarmStrategyUnitTest {
    using stdStorage for StdStorage;

    address public morpho;
    address public rewardAsset;

    function _setUp() internal override {
        rewardAsset = BaseGetter.getBaseERC20(18);
        morpho = address(new MorphoMock(asset));

        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = rewardAsset;

        // Farm asset and borrow asset are the same
        address[] memory nonSkimableAssets = new address[](2);
        nonSkimableAssets[0] = asset;
        nonSkimableAssets[1] = rewardAsset;

        farmStrategy = new MorphoVault(
            dispatcher,
            address(this),
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            IERC4626(morpho),
            rewardAssets,
            nonSkimableAssets
        );
    }

    function test_CorrectInitialization() public view {
        MorphoVault moprhoStrategy = MorphoVault(address(farmStrategy));

        assertEq(address(moprhoStrategy.morphoVault()), morpho);
        assertEq(moprhoStrategy.rewardAssets(0), rewardAsset);
    }

    function test_SetRewardsAsset() public {
        MorphoVault moprhoStrategy = MorphoVault(address(farmStrategy));

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = BaseGetter.getBaseERC20(18);
        rewardAssets[1] = BaseGetter.getBaseERC20(18);

        moprhoStrategy.setRewardAssets(rewardAssets);
        assertEq(moprhoStrategy.rewardAssets(0), rewardAssets[0]);
        assertEq(moprhoStrategy.rewardAssets(1), rewardAssets[1]);
    }

    function test_NonOwnerSetsRewardsAsset() public {
        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = BaseGetter.getBaseERC20(18);

        vm.prank(vm.addr(2));
        vm.expectRevert("Ownable: caller is not the owner");
        MorphoVault(address(farmStrategy)).setRewardAssets(rewardAssets);
    }

    function test_RewardsRecognition() public {
        IToken(rewardAsset).mint(address(farmStrategy), DEPOSIT);

        farmStrategy.recogniseRewardsInBase();

        assertEq(IToken(asset).balanceOf(address(this)), DEPOSIT);
    }

    function test_RewardsRecognitionSwapFails() public {
        IToken(rewardAsset).mint(address(farmStrategy), DEPOSIT);

        vm.mockCallRevert(
            address(farmStrategy.swapStrategy()),
            abi.encodeWithSelector(ISwapStrategy.swapInBase.selector, rewardAsset, asset, DEPOSIT),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        vm.expectRevert("SWAP_STRATEGY_SWAP_NOT_PROCEEDED");
        farmStrategy.recogniseRewardsInBase();
    }

    function _assertDeposit() internal view override {
        assertEq(IToken(farmStrategy.farmAsset()).balanceOf(morpho), DEPOSIT);
    }

    function _changeFarmAsset() internal override returns (address newFarmAsset) {
        newFarmAsset = BaseGetter.getBaseERC20(18);
        // Update storage to enforce swap
        stdstore.target(address(farmStrategy)).sig("farmAsset()").checked_write(newFarmAsset);

        stdstore.target(address(morpho)).sig("asset()").checked_write(newFarmAsset);
    }
}
