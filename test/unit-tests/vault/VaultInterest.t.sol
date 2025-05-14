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

    function test_BorrowLoss() public {
        address aliceUser = makeAddr("aliceUser");
        address bobUser = makeAddr("bobUser");
        depositAndBorrow(aliceUser);
        depositAndBorrow(bobUser);
        // alice 10/5, bob 10/5, lender 20/10

        accumulateInterest(DEPOSIT, BORROW);
        // alice 15/7.5, bob 15/7.5, lender 30/15

        depositAndBorrow(bobUser);
        // alice 15/7.5, bob 25/12.5, lender 40/20
        // index & principal snapshot
        uint256 aliceBalance = vault.debtToken().balanceOf(aliceUser);
        uint256 bobBalance = vault.debtToken().balanceOf(bobUser);

        accumulateInterest(DEPOSIT, BORROW);
        // lender 50/25

        assertGt(vault.debtToken().balanceOf(aliceUser), aliceBalance);
        assertGt(vault.debtToken().balanceOf(bobUser), bobBalance);
        uint256 storedIndexBeforeLoss = vault.debtToken().interestIndex();
        uint256 borrowPrincipal = BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal();
        assertGt(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss);

        simulateSupplyLoss(0, 50, 0);
        // lender 50/12.5
        uint256 lenderBalance = BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance();

        assertGt(
            BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal(),
            BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance(),
            "Borrow loss conditions"
        );
        assertEq(vault.debtToken().balanceOf(aliceUser), aliceBalance);
        assertEq(vault.debtToken().balanceOf(bobUser), bobBalance);
        assertEq(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Freeze the index");
        assertEq(vault.reserveAmount(), 0);

        uint256 lossAmount = BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal() -
            BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance();

        repay(aliceUser);
        aliceBalance -= REPAY;
        // repay 2, principal 18, lender 10.5
        borrowPrincipal -= REPAY;
        lenderBalance -= REPAY;
        assertEq(borrowPrincipal, BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal());
        // repay 12.5, principal 5.5, lender 0
        repay(bobUser, bobBalance);
        assertEq(vault.reserveAmount(), bobBalance - lenderBalance, "Overpayment goes to the vault reserve");
        assertEq(BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance(), 0, "Lender fully repaid");
        borrowPrincipal -= bobBalance;
        bobBalance -= bobBalance;
        lenderBalance = 0;

        depositAndBorrow(aliceUser);
        borrowPrincipal += BORROW;
        lenderBalance += BORROW;
        aliceBalance += BORROW;
        // borrow 5, principal 10.5, lender 5

        assertEq(BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance(), lenderBalance);
        assertEq(BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal(), borrowPrincipal);
        assertEq(vault.debtToken().balanceOf(aliceUser), aliceBalance);
        assertEq(vault.debtToken().balanceOf(bobUser), 0);

        assertEq(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Freeze the index");

        accumulateInterest(0, borrowPrincipal - lenderBalance + 2e6);

        assertApproxEqAbs(vault.debtToken().balanceOf(aliceUser), aliceBalance + 2e6, 1);

        assertGt(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Resume the index");
    }

    function test_ReconcileBorrowLoss() public {
        address aliceUser = makeAddr("aliceUser");
        address bobUser = makeAddr("bobUser");
        depositAndBorrow(aliceUser);
        depositAndBorrow(bobUser);
        // alice 10/5, bob 10/5, lender 20/10

        accumulateInterest(DEPOSIT, BORROW);
        // alice 15/7.5, bob 15/7.5, lender 30/15

        depositAndBorrow(bobUser);
        // alice 15/7.5, bob 25/12.5, lender 40/20
        // index & principal snapshot
        uint256 storedIndexBeforeLoss = vault.debtToken().interestIndex();

        accumulateInterest(DEPOSIT, BORROW);
        // lender 50/25
        assertGt(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Index incraesing normally");

        simulateSupplyLoss(0, 50, 0);
        // lender 50/12.5, principal 20
        uint256 borrowBalance = BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance();
        uint256 borrowPrincipal = BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal();

        assertGt(
            BaseLenderStrategy(vault.activeLenderStrategy()).borrowPrincipal(),
            BaseLenderStrategy(vault.activeLenderStrategy()).borrowBalance(),
            "Borrow loss conditions"
        );

        assertEq(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Freeze the index");

        accumulateInterest(DEPOSIT, BORROW);
        borrowBalance += BORROW;
        // lender 60/17.5, principal 20
        assertEq(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Freeze the index");

        vm.startPrank(address(deployer));
        BaseLenderStrategy(vault.activeLenderStrategy()).reconcileBorrowLoss();
        vm.stopPrank();

        assertEq(vault.reserveAmount(), borrowPrincipal - borrowBalance);
        accumulateInterest(DEPOSIT, BORROW);

        assertGt(vault.debtToken().calcNewIndex(), storedIndexBeforeLoss, "Resume the index");
    }
}
