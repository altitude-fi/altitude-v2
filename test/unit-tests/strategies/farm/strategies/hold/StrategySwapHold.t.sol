// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FarmStrategyUnitTest} from "../FarmStrategyUnitTest.sol";
import {StrategySwapHold} from "../../../../../../contracts/strategies/farming/strategies/hold/StrategySwapHold.sol";

import {IToken} from "../../../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";
import {ISwapHoldStrategy} from "../../../../../../contracts/interfaces/internal/strategy/farming/ISwapHoldStrategy.sol";

contract StrategySwapHoldTest is FarmStrategyUnitTest {
    address public farmAsset;
    address[] public rewardAssets;

    function _setUp() internal override {
        farmAsset = BaseGetter.getBaseERC20(18);

        rewardAssets = new address[](1);
        rewardAssets[0] = BaseGetter.getBaseERC20(18);

        farmStrategy = new StrategySwapHold(
            farmAsset,
            dispatcher,
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            rewardAssets
        );
    }

    function test_RewardsRecognition() public {
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        // Simulate interest accumulation
        IToken(farmAsset).mint(address(farmStrategy), DEPOSIT);
        // Simulate rewards airdrop
        IToken(rewardAssets[0]).mint(address(farmStrategy), DEPOSIT);

        assertEq(farmStrategy.balance(), DEPOSIT * 2);

        farmStrategy.recogniseRewardsInBase();
        vm.stopPrank();

        assertEq(IToken(asset).balanceOf(dispatcher), DEPOSIT);
        assertEq(IToken(asset).balanceOf(address(farmStrategy)), 0);
        assertEq(IToken(farmAsset).balanceOf(address(farmStrategy)), DEPOSIT * 2);
        assertEq(ISwapHoldStrategy(address(farmStrategy)).balance(), DEPOSIT * 2);
    }

    function test_EmergencyWithdraw() public {
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        farmStrategy.emergencyWithdraw();
        address[] memory assets = new address[](1);
        assets[0] = farmAsset;
        farmStrategy.emergencySwap(assets);

        assertEq(farmStrategy.balance(), 0, "strategy empty");
        assertEq(IToken(asset).balanceOf(dispatcher), DEPOSIT, "funds at dispatcher");
        assertEq(IToken(farmAsset).balanceOf(address(farmStrategy)), 0, "strategy empty");
    }

    function _assertDeposit() internal view override {
        assertEq(IToken(asset).balanceOf(address(farmStrategy)), 0);
        assertEq(IToken(farmAsset).balanceOf(address(farmStrategy)), DEPOSIT);
        assertEq(ISwapHoldStrategy(address(farmStrategy)).balance(), DEPOSIT);
    }

    function _changeFarmAsset() internal view override returns (address newFarmAsset) {
        newFarmAsset = farmStrategy.farmAsset();
    }
}
