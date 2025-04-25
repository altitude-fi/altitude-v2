// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";
import {BaseLenderStrategy} from "../../base/BaseLenderStrategy.sol";
import {BorrowVerifierSigUtils} from "../../utils/BorrowVerifierSigUtils.sol";

import {VaultTypes} from "../../../contracts/libraries/types/VaultTypes.sol";
import {HarvestTypes} from "../../../contracts/libraries/types/HarvestTypes.sol";

import {IBorrowVerifier} from "../../../contracts/interfaces/internal/misc/IBorrowVerifier.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";

contract VaultCoreTest is VaultTestSuite {
    IFarmDispatcher public dispatcher;
    ILenderStrategy public lenderStrategy;

    function setUp() public override {
        super.setUp();

        dispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
    }

    function test_Deposit() public {
        address user = vm.addr(1);
        deposit(user);

        assertEq(lenderStrategy.supplyBalance(), DEPOSIT);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
        assertEq(vault.userLastDepositBlock(user), block.number);
        HarvestTypes.UserHarvestData memory userData = vault.getUserHarvest(user);
        assertEq(userData.harvestJoiningBlock, block.number);
    }

    function test_DepositZero() public {
        vm.expectRevert(IVaultCoreV1.VC_V1_INVALID_DEPOSIT_AMOUNT.selector);
        vault.deposit(0, address(this));
    }

    function test_DepositOnBehalf() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);

        address[] memory allowee = new address[](1);
        allowee[0] = user2;

        vm.prank(user);
        vault.allowOnBehalf(allowee, true);

        deposit(user2, user);

        assertEq(lenderStrategy.supplyBalance(), DEPOSIT);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
        assertEq(vault.userLastDepositBlock(user), block.number);
        HarvestTypes.UserHarvestData memory userData = vault.getUserHarvest(user);
        assertEq(userData.harvestJoiningBlock, block.number);
    }

    function test_DepositOnBehalfNotAllowed() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);
        vm.startPrank(user2);
        mintToken(deployer.supplyAsset(), user2, DEPOSIT);
        IToken(deployer.supplyAsset()).approve(address(vault), DEPOSIT);
        vm.stopPrank();

        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_ALLOWED_TO_ACT_ON_BEHALF.selector);
        vm.prank(user2);
        vault.deposit(DEPOSIT, user);
    }

    function test_DepositOnBehalfAllowedWhenFunctionDisabled() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);
        vm.startPrank(user2);
        mintToken(deployer.supplyAsset(), user2, DEPOSIT);
        IToken(deployer.supplyAsset()).approve(address(vault), DEPOSIT);
        vm.stopPrank();

        bytes4[] memory functions = new bytes4[](1);
        functions[0] = IVaultCoreV1.deposit.selector;
        vm.prank(address(vaultRegistry));
        vault.disableOnBehalfValidation(functions, true);

        vm.prank(user2);
        vault.deposit(DEPOSIT, user);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
    }

    function test_BorrowFromTheLenderProvider() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        assertEq(lenderStrategy.borrowBalance(), BORROW);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
    }

    function test_BorrowPartiallyFromTheFarmProvider() public {
        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider
        vault.rebalance();

        // User deposits one more time to increase the available balance into the lender
        depositAndBorrow(user, DEPOSIT / 2);

        uint256 expectedLenderBalance = 105e5; // Price 1:1. Rebalance borrows up to 70% from 15e18 in borrow decimals(6)= 10.5e5

        assertEq(dispatcher.balance(), expectedLenderBalance - BORROW);
        assertEq(lenderStrategy.borrowBalance(), expectedLenderBalance);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
    }

    function test_BorrowFullyFromTheFarmProvider() public {
        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider
        vault.rebalance();

        // Withdraw everything from the farm
        vm.prank(user);
        vault.borrow(BORROW);

        uint256 expectedLenderBalance = 7e6; // Price 1:1. Rebalance borrows up to 70% from 10e18 in borrow decimals(6)= 7e6

        assertEq(dispatcher.balance(), expectedLenderBalance - BORROW);
        assertEq(lenderStrategy.borrowBalance(), expectedLenderBalance);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
    }

    function test_BorrowZero() public {
        address user = vm.addr(1);
        deposit(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_INVALID_BORROW_AMOUNT.selector);
        vm.prank(user);
        vault.borrow(0);
    }

    function test_BorrowMakingUnhealthyLTV() public {
        address user = vm.addr(1);
        deposit(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_ENOUGH_SUPPLY.selector);
        vm.prank(user);
        vault.borrow(BORROW * 3); // Borrow to much
    }

    function test_BorrowFromTheFarmProviderNotEnoughFunds() public {
        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider
        vault.rebalance();

        // Simulate not enough funds
        vm.mockCall(address(dispatcher), abi.encodeWithSelector(IFarmDispatcher.withdraw.selector), abi.encode(0));

        vm.expectRevert(IVaultCoreV1.VC_V1_FARM_WITHDRAW_INSUFFICIENT.selector);
        vm.prank(user);
        vault.borrow(BORROW);
    }

    function test_BorrowOnBehalfOf() public {
        (address user, address user2, bytes memory signature) = BorrowVerifierSigUtils.approveBorrow(
            vm,
            address(vault.borrowVerifier()),
            BORROW
        );

        deposit(user);

        vm.prank(user2);
        vault.borrowOnBehalfOf(BORROW, user, 1 days, signature);

        assertEq(lenderStrategy.borrowBalance(), BORROW);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), 0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user2), BORROW);
    }

    function test_BorrowOnBehalfOfInvalidSigner() public {
        (address user, , bytes memory signature) = BorrowVerifierSigUtils.approveBorrow(
            vm,
            address(vault.borrowVerifier()),
            BORROW
        );

        deposit(user);

        vm.expectRevert(IBorrowVerifier.BV_INVALID_SIGNATURE.selector);
        vm.prank(vm.addr(3));
        vault.borrowOnBehalfOf(BORROW, user, 1 days, signature);
    }

    function test_BorrowOnBehalfExpiredApproval() public {
        (address user, address user2, bytes memory signature) = BorrowVerifierSigUtils.approveBorrow(
            vm,
            address(vault.borrowVerifier()),
            BORROW
        );

        deposit(user);
        // Time travel with timestamp
        vm.warp(1 days + 1 seconds);

        vm.expectRevert(IBorrowVerifier.BV_DEADLINE_PASSED.selector);
        vm.prank(user2);
        vault.borrowOnBehalfOf(BORROW, user, 1 days, signature);
    }

    function test_Repay() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        repay(user);

        assertEq(lenderStrategy.borrowBalance(), BORROW - REPAY);
        assertEq(vault.debtToken().balanceOf(user), BORROW - REPAY);
        // repay() has minted REPAY amount for the user to have money to repay with
        // Because of that the user balance is equal to the amount he has borrowed
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
        HarvestTypes.UserHarvestData memory userData = vault.getUserHarvest(user);
        assertEq(userData.harvestJoiningBlock, block.number);
    }

    function test_RepayPartiallyOnBehalf() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);

        address[] memory allowee = new address[](1);
        allowee[0] = user2;
        vm.prank(user);
        vault.allowOnBehalf(allowee, true);

        depositAndBorrow(user);
        repay(user2, user);

        assertEq(lenderStrategy.borrowBalance(), BORROW - REPAY);
        assertEq(vault.debtToken().balanceOf(user), BORROW - REPAY);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user2), 0);
        HarvestTypes.UserHarvestData memory userData = vault.getUserHarvest(user);
        assertEq(userData.harvestJoiningBlock, block.number);
    }

    function test_RepayFullyOnBehalf() public {
        address user = vm.addr(1);
        address user2 = vm.addr(2);

        address[] memory allowee = new address[](1);
        allowee[0] = user2;
        vm.prank(user);
        vault.allowOnBehalf(allowee, true);

        depositAndBorrow(user);
        repay(user2, user, BORROW);

        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user2), 0);
        HarvestTypes.UserHarvestData memory userData = vault.getUserHarvest(user);
        assertEq(userData.harvestJoiningBlock, block.number);
    }

    function test_RepayZero() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_INVALID_REPAY_AMOUNT.selector);
        vm.prank(user);
        vault.repay(0, user);
    }

    function test_RepayNoDebt() public {
        // User has no debt
        address user = vm.addr(1);
        deposit(user);

        // Mint tokens for the repayment
        repay(user);

        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), REPAY);
    }

    function test_RepayMoreThanUserBalance() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        // Borrow more to try to repay more
        repay(user, user, BORROW * 2);

        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
        // repay() mints the amount needed for repayment behind the scene
        //  That is why we end up with 3xBORROW amount (1 from borrow and 2 from repay)
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW * 2);
    }

    function test_RepayMoreThanLenderBalance() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        // Simulate vault debt lower than the repayment amount
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IToken.balanceOf.selector, user),
            abi.encode(BORROW * 2)
        );

        repay(user, user, BORROW * 2);

        assertEq(lenderStrategy.borrowBalance(), 0);
        // repay() mints the amount needed for repayment behind the scene
        //  That is why we end up with 3xBORROW amount (1 from borrow and 2 from repay)
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(address(vault)), BORROW);
    }

    function test_WithdrawFromTheLenderProvider() public {
        address user = vm.addr(1);
        depositAndWithdraw(user);

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT);
    }

    function test_WithdrawPartiallyFromTheFarmProvider() public {
        address user = vm.addr(1);
        deposit(user, user, DEPOSIT * 2);

        // Deposit into the farm provider
        vault.rebalance();
        depositAndWithdraw(user, DEPOSIT, WITHDRAW * 2);

        uint256 expectedLenderBalance = 7e6; // Price 1:1. Rebalance borrows up to 70% from 1e18 in borrow decimals(6)= 7e6
        assertEq(dispatcher.balance(), expectedLenderBalance);

        assertEq(lenderStrategy.supplyBalance(), DEPOSIT);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT * 2);
    }

    function test_WithdrawFullyFromTheFarmProvider() public {
        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider
        vault.rebalance();

        vm.prank(user);
        vault.withdraw(WITHDRAW, user);

        assertEq(dispatcher.balance(), 0);
        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT);
    }

    // That case could happen due to negative users or farm loss that has not been recognized yet
    function test_WithdrawFromTheFarmProviderNoMoreThanVaultDebt() public {
        // Increase the difference between the target and liquidation thresholds
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(7e17, 7e17, 2e17)
        );

        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider 2e6 based on the target threshold of 2e17
        vault.rebalance();

        // Simulate withdraw from the farm provider up to the vault debt balance
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IToken.balanceOf.selector, address(vault)),
            abi.encode(1e6) // Price 1:1. Rebalance borrows up to 20% from 10e18 in borrow decimals(6)= 2e6.
            // We are setting it to 1e6 simulating loss
        );

        vm.prank(user);
        // Withdraws amount bigger than the farm balance(1e6) but small enough to not trigger vault unhealthy check
        // In practice the loss of 1e6 will stay in the vault to be repaid. That is 70% of the deposit
        // we should leave to not trigger the unhealthy check.
        vault.withdraw(8e18, user); // leaving 2e18 that is to cover for the healthy check

        assertEq(dispatcher.balance(), 1e6); // remaining balance being skipped
        assertEq(lenderStrategy.supplyBalance(), 2e18);
        assertEq(lenderStrategy.borrowBalance(), 1e6);
        assertEq(vault.supplyToken().balanceOf(user), 2e18);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), 8e18);
    }

    function test_WithdrawFromTheFarmProviderNotEnoughFunds() public {
        address user = vm.addr(1);
        deposit(user);

        // Deposit into the farm provider
        vault.rebalance();

        // Simulate not enough funds
        vm.mockCall(address(dispatcher), abi.encodeWithSelector(IFarmDispatcher.withdraw.selector), abi.encode(0));

        vm.expectRevert(IVaultCoreV1.VC_V1_FARM_WITHDRAW_INSUFFICIENT.selector);
        vm.prank(user);
        vault.withdraw(DEPOSIT, user);
    }

    function test_WithdrawMoreThanUserBalance() public {
        address user = vm.addr(1);
        depositAndWithdraw(user, DEPOSIT, WITHDRAW * 2);

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT);
    }

    function test_WithdrawMoreThanLenderBalance() public {
        address user = vm.addr(1);
        deposit(user);

        // Simulate vault balance lower than withdraw amount
        vm.mockCall(
            address(vault.supplyToken()),
            abi.encodeWithSelector(IToken.balanceOf.selector, user),
            abi.encode(DEPOSIT * 2)
        );

        vm.prank(user);
        vault.withdraw(WITHDRAW * 2, user);

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT);
    }

    function test_WithdrawZero() public {
        address user = vm.addr(1);
        deposit(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_INVALID_WITHDRAW_AMOUNT.selector);
        vm.prank(user);
        vault.withdraw(0, user);
    }

    function test_WithdrawMakingUnhealthyLTV() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_ENOUGH_SUPPLY.selector);
        vm.prank(user);
        vault.withdraw(WITHDRAW, user); // Withdraws to much
    }

    function test_HealthyUserPositionWithdrawMakingUnhealthyLTV() public {
        // That is in the case of negative users
        address user = vm.addr(1);
        depositAndBorrow(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_ENOUGH_SUPPLY.selector);
        vm.prank(user);
        vault.withdraw(WITHDRAW, user); // Withdraws to much
    }

    function test_WithdrawFeeDistributionWhenManyUsers() public {
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(
                address(vault.borrowVerifier()),
                1e17, // 10% fee tax
                1000, // 1000 blocks fee
                vault.configurableManager(),
                vault.swapStrategy(),
                vault.ingressControl()
            )
        );

        address user = vm.addr(1);
        address user2 = vm.addr(2);

        deposit(user);
        depositAndWithdraw(user2);

        assertEq(IToken(deployer.supplyAsset()).balanceOf(user2), DEPOSIT - (DEPOSIT / 10)); // withdraw - 10%
        assertEq(vault.supplyToken().balanceOf(user2), 0);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT + (DEPOSIT / 10)); // deposit + 10% being distributed

        // Time travel with blocks
        vm.roll(block.number + 1001);

        // Check if user can withdraw the fee from the other one
        vm.prank(user);
        vault.withdraw(DEPOSIT + (DEPOSIT / 10), user);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT + (DEPOSIT / 10));
    }

    function test_WithdrawFeeStaysForTheProtocolWhenOneUser() public {
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(
                address(vault.borrowVerifier()),
                1e17, // 10% fee tax
                1000, // 1000 blocks fee
                vault.configurableManager(),
                vault.swapStrategy(),
                vault.ingressControl()
            )
        );

        address user = vm.addr(1);
        uint256 halfWithdraw = WITHDRAW / 2;
        depositAndWithdraw(user, DEPOSIT, halfWithdraw);

        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), halfWithdraw - halfWithdraw / 10); // half withdraw - 10%
        // check the tax is not getting distributed to the same user
        assertEq(vault.supplyToken().balanceOf(user), halfWithdraw);
        // check the tax stays in the protocol (LOCKED)
        assertEq(lenderStrategy.supplyBalance(), halfWithdraw + halfWithdraw / 10);
    }

    function test_WithdrawFeeStaysForTheProtocolEvenUserRejoins() public {
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(
                address(vault.borrowVerifier()),
                1e17, // 10% fee tax
                1000, // 1000 blocks fee
                vault.configurableManager(),
                vault.swapStrategy(),
                vault.ingressControl()
            )
        );

        address user = vm.addr(1);
        depositAndWithdraw(user);
        deposit(user);

        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), WITHDRAW - WITHDRAW / 10); // withdraw - 10%

        // check the tax is not getting distributed to the user if he rejoins
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
        // check the tax stays in the protocol (LOCKED)
        assertEq(lenderStrategy.supplyBalance(), DEPOSIT + WITHDRAW / 10);
    }

    function test_WithdrawWithLenderFee() public {
        address user = vm.addr(1);
        deposit(user);

        // Simulate lender fee
        BaseLenderStrategy(address(lenderStrategy)).setWithdrawFee(1e17); // 10%

        vm.prank(user);
        vault.withdraw(WITHDRAW, user);

        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), WITHDRAW - WITHDRAW / 10);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(lenderStrategy.supplyBalance(), 0);
    }

    function test_WithdrawTaxFeeWithLenderFee() public {
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(
                address(vault.borrowVerifier()),
                1e17, // 10% fee tax
                1000, // 1000 blocks fee
                vault.configurableManager(),
                vault.swapStrategy(),
                vault.ingressControl()
            )
        );

        address user = vm.addr(1);
        deposit(user);

        // Simulate lender fee
        BaseLenderStrategy(address(lenderStrategy)).setWithdrawFee(1e17); // 10%

        vm.prank(user);
        vault.withdraw(WITHDRAW, user);

        // Charge tax fee of 10% and then another 10% of the amount as a lender fee
        uint256 amountAfterTaxFee = WITHDRAW - WITHDRAW / 10;
        assertEq(
            IToken(deployer.supplyAsset()).balanceOf(user),
            amountAfterTaxFee - amountAfterTaxFee / 10 // another 10% as a lender fee
        );
        assertEq(vault.supplyToken().balanceOf(user), 0);

        // check the tax stays in the protocol (LOCKED)
        assertEq(vault.supplyToken().totalSupply(), WITHDRAW / 10);
        assertEq(lenderStrategy.supplyBalance(), WITHDRAW / 10);
    }

    function test_DepositAndBorrow() public {
        address user = vm.addr(1);

        vm.startPrank(user);
        mintToken(deployer.supplyAsset(), user, DEPOSIT);
        IToken(deployer.supplyAsset()).approve(address(vault), DEPOSIT);
        vault.depositAndBorrow(DEPOSIT, BORROW);
        vm.stopPrank();

        assertEq(lenderStrategy.borrowBalance(), BORROW);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW);
    }

    function test_RepayAndWithdraw() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        vm.startPrank(user);
        IToken(deployer.borrowAsset()).approve(address(vault), BORROW);
        vault.repayAndWithdraw(BORROW, WITHDRAW, user);
        vm.stopPrank();

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
        assertEq(IToken(deployer.supplyAsset()).balanceOf(user), DEPOSIT);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), 0);
    }

    // Bad debt happens when the price drops by such a big amount
    // so when a liquidator liquidates the user's position, it repays up to the supply balance,
    // but there is still debt amount remaining unpaid
    function test_RepayBadDebt() public {
        uint256 maxBorrow = 7e6; // Borrow up to the target threshold
        address user = vm.addr(1);
        depositAndBorrow(user, DEPOSIT, maxBorrow);

        // Simulate the user is for liquidation
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(6e17, 6e17, 6e17)
        );

        address[] memory liquidationUsers = new address[](1);
        liquidationUsers[0] = user;

        // Obtain tokens for liquidation the position
        mintToken(deployer.borrowAsset(), address(this), maxBorrow);
        IToken(deployer.borrowAsset()).approve(address(vault), maxBorrow);

        // Simulate a drastic price drop
        vm.mockCall(
            vault.activeLenderStrategy(),
            abi.encodeWithSelector(ILenderStrategy.getInBase.selector, deployer.borrowAsset(), deployer.supplyAsset()),
            abi.encode(10 ** IToken(deployer.supplyAsset()).decimals() * 2) // make the price 2:1 for defaulting positions
        );

        vault.liquidateUsers(liquidationUsers, maxBorrow);

        assertTrue(lenderStrategy.borrowBalance() > 0);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        // Initially one has 10 deposited and 7 borrowed
        // Price goes down by 50% meaning the one has 5 deposited and 7 borrowed
        // There is 1% liquidation bonus which ends in x * 1.01 = 5 => x = 4.950495 debt
        // x = amount needed to be repaid for receiving back the entire supply
        assertEq(vault.debtToken().balanceOf(user), maxBorrow - 4950495);

        IToken(deployer.borrowAsset()).approve(address(vault), maxBorrow - 4950495);
        vault.repayBadDebt(maxBorrow - 4950495, user);
        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(vault.supplyToken().balanceOf(user), 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
    }

    function test_RepayBadDebtWhenHavingSupply() public {
        address user = vm.addr(1);
        deposit(user);

        vm.expectRevert(IVaultCoreV1.VC_V1_USER_HAS_SUPPLY.selector);
        vault.repayBadDebt(REPAY, user);
    }

    function test_NonSupplyTokenPreTransfer() public {
        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_AUTHORIZED_TO_DEAL_WITH_TRANSFERS.selector);
        vault.preTransfer(address(0), address(0), 0, 0x12345678);
    }

    function test_NonSupplyTokenPostTransfer() public {
        vm.expectRevert(IVaultCoreV1.VC_V1_NOT_AUTHORIZED_TO_DEAL_WITH_TRANSFERS.selector);
        vault.postTransfer(address(0), address(0));
    }

    // Borrowing with a target threshold of 0 should go through
    function test_ZeroTargetThresholdBorrow() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();
        harvestWithRewards();

        vault.updatePosition(user);

        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(7e17, 8e17, 0)
        );

        vault.rebalance();

        vm.prank(user);
        vault.borrow(2e6);

        assertEq(lenderStrategy.borrowBalance(), 2e6);
    }
}
