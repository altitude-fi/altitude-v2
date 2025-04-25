// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IToken} from "../../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {ISwapStrategy} from "../../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {IFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IFarmStrategy.sol";

abstract contract FarmStrategyUnitTest is Test {
    uint256 public DEPOSIT = 1e18;

    address public asset;
    address public dispatcher;
    IFarmStrategy public farmStrategy;

    function setUp() public {
        asset = BaseGetter.getBaseERC20(18);

        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), asset, address(this));

        _setUp();
    }

    function test_DepositWithNoSwap() public {
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        _assertDeposit();
    }

    function test_DepositWithSwap() public {
        _changeFarmAsset();
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        _assertDeposit();
    }

    function test_DepositWithSwapFails() public {
        address newFarmAsset = _changeFarmAsset();
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);

        vm.mockCallRevert(
            address(farmStrategy.swapStrategy()),
            abi.encodeWithSelector(ISwapStrategy.swapInBase.selector, asset, newFarmAsset, DEPOSIT),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        vm.expectRevert("SWAP_STRATEGY_SWAP_NOT_PROCEEDED");
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();
    }

    function test_WithdrawLessThenBalance() public {
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        farmStrategy.withdraw(DEPOSIT / 2);
        uint256 amountWithdrawn = IToken(asset).balanceOf(dispatcher);
        vm.stopPrank();

        assertEq(amountWithdrawn, DEPOSIT / 2, "Withdraw half");
    }

    function test_WithdrawMoreThenBalance() public {
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        farmStrategy.withdraw(DEPOSIT * 2);
        uint256 amountWithdrawn = IToken(asset).balanceOf(dispatcher);
        vm.stopPrank();

        assertEq(amountWithdrawn, DEPOSIT);
    }

    function test_WithdrawWithSwap() public {
        _changeFarmAsset();
        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        farmStrategy.withdraw(DEPOSIT);
        uint256 amountWithdrawn = IToken(asset).balanceOf(dispatcher);
        vm.stopPrank();

        assertEq(amountWithdrawn, DEPOSIT);
    }

    function test_WithdrawWithSwapFails() public {
        address newFarmAsset = _changeFarmAsset();

        IToken(asset).mint(dispatcher, DEPOSIT);

        vm.startPrank(dispatcher);
        IToken(asset).approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        vm.mockCallRevert(
            address(farmStrategy.swapStrategy()),
            abi.encodeWithSelector(ISwapStrategy.swapInBase.selector, newFarmAsset, asset, DEPOSIT),
            "SWAP_STRATEGY_SWAP_NOT_PROCEEDED"
        );
        vm.expectRevert("SWAP_STRATEGY_SWAP_NOT_PROCEEDED");
        farmStrategy.withdraw(DEPOSIT);
        vm.stopPrank();
    }

    function _setUp() internal virtual;

    function _assertDeposit() internal view virtual;

    function _changeFarmAsset() internal virtual returns (address newFarmAsset);
}
