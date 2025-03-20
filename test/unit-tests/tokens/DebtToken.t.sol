// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {BaseGetter} from "../../base/BaseGetter.sol";

import {DebtToken} from "../../../contracts/tokens/DebtToken.sol";
import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";

import {IDebtToken} from "../../../contracts/interfaces/internal/tokens/IDebtToken.sol";
import {IVaultCoreV1} from "../../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {ISnapshotableVaultV1} from "../../../contracts/interfaces/internal/vault/extensions/snapshotable/ISnapshotableVault.sol";

contract DebtTokenTest is Test {
    DebtToken public debtToken;

    address public vault;
    address[] public users;
    address public lenderStrategy;

    function setUp() public {
        users = new address[](2);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        lenderStrategy = makeAddr("lenderStrategy");

        // Deploy DebtToken
        debtToken = new DebtToken();
        debtToken.initialize("debt", "debt", address(this), BaseGetter.getBaseERC20(6), lenderStrategy, 1e20);

        // Mock vault functions
        vm.mockCall(address(this), abi.encodeWithSelector(IVaultCoreV1.preTransfer.selector), abi.encode());
        vm.mockCall(address(this), abi.encodeWithSelector(IVaultCoreV1.postTransfer.selector), abi.encode());
    }

    function test_RevertTransfer() public {
        vm.expectRevert(IDebtToken.DT_TRANSFER_NOT_SUPPORTED.selector);
        debtToken.transfer(users[1], 1e18);
    }

    function test_RevertTransferFrom() public {
        vm.expectRevert(IDebtToken.DT_TRANSFER_NOT_SUPPORTED.selector);
        debtToken.transferFrom(users[0], users[1], 1e18);
    }

    function test_RevertApprove() public {
        vm.expectRevert(IDebtToken.DT_APPROVAL_NOT_SUPPORTED.selector);
        debtToken.approve(users[1], 1e18);
    }

    function test_RevertIncreaseAllowance() public {
        vm.expectRevert(IDebtToken.DT_ALLOWANCE_INCREASE_NOT_SUPPORTED.selector);
        debtToken.increaseAllowance(users[1], 1e18);
    }

    function test_RevertDecreaseAllowance() public {
        vm.expectRevert(IDebtToken.DT_ALLOWANCE_DECREASE_NOT_SUPPORTED.selector);
        debtToken.decreaseAllowance(users[1], 1e18);
    }

    // Should calculate the accrued balance and subtract the farm earnings
    function test_BalanceOf() public {
        debtToken.mint(users[0], 7e6);

        // Accumulate interest
        _setBorrowPrincipal(7e6);
        _setBorrowBalance(7.5e6);

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector),
            abi.encode(
                0,
                0,
                0,
                0,
                7e5, // farm earnings
                0,
                CommonTypes.UserPosition(0, 0, 1e20, 7e6)
            )
        );

        assertApproxEqAbs(debtToken.balanceOf(users[0]), 6.8e6, 10); // 10 wei rounding tolerance
    }

    function test_BalanceOf_EarningsCoverEntireDebt() public {
        debtToken.mint(users[0], 7e6);

        // Accumulate interest
        _setBorrowPrincipal(7e6);
        _setBorrowBalance(7.5e6);

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector),
            abi.encode(
                0,
                0,
                0,
                0,
                7e5, // farm earnings
                0,
                CommonTypes.UserPosition(0, 0, 7.50000107142857142857142858e26, 7.5e6)
            )
        );

        assertEq(debtToken.balanceOf(users[0]), 0);
    }

    function test_BalanceOfAt_EarningsCoverPartialDebt() public {
        debtToken.mint(users[0], 7e6);

        // Accumulate interest
        _setBorrowPrincipal(7e6);
        _setBorrowBalance(7.5e6);

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector),
            abi.encode(
                0,
                0,
                100000e18,
                0,
                7e5, // farm earnings
                0,
                CommonTypes.UserPosition(0, 0, 1.02040816326530612244e20, 7.5e6)
            )
        );

        assertEq(debtToken.balanceOfAt(users[0], 0), 0);
    }

    function _setBorrowBalance(uint256 amount) internal {
        vm.mockCall(lenderStrategy, abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector), abi.encode(amount));
    }

    function _setBorrowPrincipal(uint256 amount) internal {
        vm.mockCall(
            lenderStrategy,
            abi.encodeWithSelector(ILenderStrategy.borrowPrincipal.selector),
            abi.encode(amount)
        );
    }
}
