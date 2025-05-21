// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import {BaseFarmStrategy} from "../../../base/BaseFarmStrategy.sol";
import {IFarmStrategy} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmStrategy.sol";
import {ISwapStrategy} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {IFarmDispatcher} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {ISwapStrategyConfiguration} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategyConfiguration.sol";

contract FarmStrategyTest is Test {
    BaseFarmStrategy public farmStrategy;
    address public workingAsset;
    uint256 public constant DEPOSIT = 1e6;

    function setUp() public {
        workingAsset = BaseGetter.getBaseERC20(18);
        vm.mockCall(address(this), abi.encodeWithSelector(IFarmDispatcher.asset.selector), abi.encode(workingAsset));
        farmStrategy = BaseFarmStrategy(
            BaseGetter.getBaseFarmStrategy(workingAsset, address(this), new address[](0), address(this))
        );
    }

    function test_CorrectInitialization() public view {
        assertEq(farmStrategy.farmAsset(), workingAsset);
        assertEq(farmStrategy.farmDispatcher(), address(this));
        assertEq(farmStrategy.rewardsRecipient(), address(this));
        assertEq(farmStrategy.asset(), workingAsset);
    }

    function test_Deposit() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), DEPOSIT);
    }

    function test_NonDispatcherDeposits() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(IFarmStrategy.FS_ONLY_DISPATCHER.selector);
        farmStrategy.deposit(DEPOSIT);
    }

    function test_Withdraw() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.withdraw(DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(this)), DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), 0);
    }

    function test_WithdrawHalfAmount() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.withdraw(DEPOSIT / 2);
        // As the deposit behind the scene leaves simply the amount into the balance,
        // on withdrawal the balance is used to be returned back.
        // That being said, the withdraw could return more which is handled in the Dispatcher afterwards
        assertEq(IToken(workingAsset).balanceOf(address(this)), DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), 0);
    }

    function test_WithdrawAll() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.withdraw(type(uint256).max);
        // Can not withdraw more then the balance
        assertEq(IToken(workingAsset).balanceOf(address(this)), DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), 0);
    }

    function test_WithdrawZero() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.withdraw(0);
        // Can not withdraw more then the balance
        assertEq(IToken(workingAsset).balanceOf(address(this)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), DEPOSIT);
    }

    function test_WithdrawUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(IFarmStrategy.FS_ONLY_DISPATCHER.selector);
        farmStrategy.withdraw(DEPOSIT);
    }

    function test_RewardsRecognition() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.recogniseRewardsInBase();
        // As the deposit amount is in the balance, it is being recognised as rewards
        assertEq(IToken(workingAsset).balanceOf(address(this)), DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), 0);
    }

    function test_EmergencyWithdrawUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmStrategy.emergencyWithdraw();
    }

    function test_EmergencySwap() public {
        IToken(workingAsset).mint(address(this), DEPOSIT);
        IToken(workingAsset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        farmStrategy.emergencyWithdraw();
        farmStrategy.emergencySwap(new address[](0));
        // As the deposit amount is in the balance, it is being withdrawn
        assertEq(IToken(workingAsset).balanceOf(address(this)), DEPOSIT);
        assertEq(IToken(workingAsset).balanceOf(address(farmStrategy)), 0);
    }

    function test_EmergencySwapUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmStrategy.emergencySwap(new address[](0));
    }

    function test_SetSwapStrategy() public {
        farmStrategy.setSwapStrategy(vm.addr(1));
        assertEq(address(farmStrategy.swapStrategy()), vm.addr(1));
    }

    function test_SetSwapStrategyUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmStrategy.setSwapStrategy(vm.addr(1));
    }

    function test_BalanceTooHighSlippage() public {
        IToken farmAsset = IToken(BaseGetter.getBaseERC20(18));
        vm.mockCall(address(this), abi.encodeWithSelector(IFarmDispatcher.asset.selector), abi.encode(farmAsset));
        farmStrategy = BaseFarmStrategy(
            BaseGetter.getBaseFarmStrategy(workingAsset, address(this), new address[](0), address(this))
        );
        farmStrategy.setFarmAssetAmount(1e18);
        farmAsset.mint(address(farmStrategy), 1e18);
        // Simulate swap functions
        vm.mockCall(address(0), abi.encodeWithSelector(ISwapStrategy.getAmountOut.selector), abi.encode(1e18));
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("getMinimumAmountOut(address,address,uint256)"))),
            abi.encode(2e18)
        );

        vm.expectRevert();
        farmStrategy.balance();
    }
}
