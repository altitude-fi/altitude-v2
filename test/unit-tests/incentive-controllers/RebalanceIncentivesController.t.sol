// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BaseGetter} from "../../base/BaseGetter.sol";
import {VaultTestSuite} from "../../utils/VaultTestSuite.sol";

import {Roles} from "../../../contracts/common/Roles.sol";
import {RebalanceIncentivesController} from "../../../contracts/misc/incentives/rebalance/RebalanceIncentivesController.sol";

import {IToken} from "../../interfaces/IToken.sol";
import {IIngress} from "../../../contracts/interfaces/internal/access/IIngress.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {IRebalanceIncentivesController} from "../../../contracts/interfaces/internal/misc/incentives/rebalance/IRebalanceIncentivesController.sol";

contract RebalanceIncentivesControllerTest is VaultTestSuite {
    IToken public rewardToken;
    RebalanceIncentivesController public controller;

    function setUp() public override {
        super.setUp();

        rewardToken = IToken(BaseGetter.getBaseERC20(18));
        controller = new RebalanceIncentivesController(
            address(rewardToken),
            address(vault),
            0.10e18, // 10% deviation below target
            0.10e18 // 10% deviation above target
        );

        IIngress(vault.ingressControl()).grantRole(Roles.GAMMA, address(controller));
    }

    function test_CorrectInitialization() public view {
        assertEq(controller.rewardToken(), address(rewardToken));
        assertEq(controller.vault(), address(vault));
        assertEq(controller.minDeviation(), 0.10e18);
        assertEq(controller.maxDeviation(), 0.10e18);
    }

    function test_MaxDeviationTooHigh() public {
        vm.expectRevert(IRebalanceIncentivesController.RIC_INVALID_DEVIATIONS.selector);
        new RebalanceIncentivesController(address(rewardToken), address(vault), 0.10e18, 1.1e18);
    }

    function test_MinDeviationHigherThanTargetThreshold() public {
        vm.expectRevert(IRebalanceIncentivesController.RIC_INVALID_DEVIATIONS.selector);
        new RebalanceIncentivesController(address(rewardToken), address(vault), 1.1e18, 0.10e18);
    }

    function test_SetDeviation() public {
        controller.setDeviation(0.5e18, 0.9e18);
        assertEq(controller.minDeviation(), 0.5e18);
        assertEq(controller.maxDeviation(), 0.9e18);
    }

    function test_SetThresholdsUnauthorized() public {
        address unauthorized = address(0x123);
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setDeviation(0.5e18, 0.9e18);
    }

    function test_CurrentThreshold() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        assertEq(controller.currentThreshold(), 0.5e18);
    }

    function test_CanRebalanceThresholdLowerThanMin() public {
        address user = vm.addr(1);
        depositAndBorrow(user, DEPOSIT, 2e6);
        assertEq(controller.canRebalance(), true);
    }

    function test_CanRebalanceThresholdHigherThanMaxButNoFarming() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 0.5e6);
        assertEq(controller.canRebalance(), false);
    }

    function test_CanRebalanceThresholdHigherThanMaxButNoFarmingVaultHasDebt() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate 100% farm loss
        vm.mockCall(
            vault.activeFarmStrategy(),
            abi.encodeWithSelector(IFarmDispatcher.balance.selector),
            abi.encode(0)
        );

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 0.5e6);
        assertEq(controller.canRebalance(), false);
    }

    function test_CanRebalanceThresholdHigherThanMaxButFarmingAndVaultHasDebt() public {
        setBorrowLimits(0, 0, 0);
        controller.setDeviation(0, 0);
        setBorrowLimits(6e17, 7e17, 7e17);

        address user = vm.addr(1);
        depositAndBorrow(user, DEPOSIT);
        vault.rebalance();

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 2e6);
        assertEq(controller.canRebalance(), true);
    }

    function test_CanRebalanceThresholdHigherThanMaxButFarmingAndVaultHasNoDebt() public {
        setBorrowLimits(0, 0, 0);
        controller.setDeviation(0, 0);
        setBorrowLimits(6e17, 7e17, 7e17);

        address user = vm.addr(1);
        depositAndBorrow(user, DEPOSIT);
        vault.rebalance();

        // Simulate target threshold to 0% and farm with reward only
        vm.mockCall(address(vault.debtToken()), abi.encodeWithSelector(IToken.balanceOf.selector), abi.encode(0));

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1e6);
        assertEq(controller.canRebalance(), false);
    }

    function test_Rebalance() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        controller.rebalance();
        assertGt(vault.debtToken().balanceOf(address(vault)), 0);
    }

    function test_CanNotRebalance() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        vm.expectRevert(IRebalanceIncentivesController.RIC_CAN_NOT_REBALANCE.selector);
        controller.rebalance();
    }

    function test_CanNotRebalanceWithZeroTargetThreshold() public {
        address user = vm.addr(1);
        deposit(user);

        vaultRegistry.reduceVaultTargetThreshold(deployer.supplyAsset(), deployer.borrowAsset(), 0);
        assertEq(controller.canRebalance(), false);
    }
}
