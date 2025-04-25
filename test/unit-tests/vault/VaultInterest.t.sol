// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";
import {IInterestVault} from "../../../contracts/interfaces/internal/vault/IInterestVault.sol";

contract VaultInterestTest is VaultTestSuite {
    function test_InterestAccumulatedBeforeInteraction() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);
        depositAndBorrow(user);
        depositAndBorrow(user2);

        // Simulate 50% interest accumulation
        accumulateInterest(DEPOSIT, BORROW);

        depositAndBorrow(user);
        depositAndBorrow(user2, DEPOSIT / 2, BORROW / 2);

        // Both users started with the same deposit and borrow amounts
        // The interest distribution should has happened based on their initial amounts rather than
        // their positions after the second deposit and borrow
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT * 2 + DEPOSIT / 2);
        assertEq(vault.debtToken().balanceOf(user), BORROW * 2 + BORROW / 2);

        assertEq(vault.supplyToken().balanceOf(user2), DEPOSIT * 2);
        assertEq(vault.debtToken().balanceOf(user2), BORROW * 2);
    }

    function test_InterestUpdateWhenSnapshotNeeded() public {
        // Simulate the need of a snapshot
        deposit(vm.addr(1));
        simulateSupplyLoss(50, 0, 0);

        vm.expectRevert(IInterestVault.IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED.selector);
        vault.deposit(0, address(this));
    }
}
