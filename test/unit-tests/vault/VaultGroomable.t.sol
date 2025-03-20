pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "forge-std/console.sol";

import "../../base/BaseGetter.sol";
import "../../utils/VaultTestSuite.sol";
import {BaseGetter} from "../../base/BaseGetter.sol";
import {BaseFlashLoanStrategy} from "../../base/BaseFlashLoanStrategy.sol";
import {Roles} from "../../../contracts/common/Roles.sol";
import {VaultTypes} from "../../../contracts/libraries/types/VaultTypes.sol";

import {IToken} from "../../interfaces/IToken.sol";
import {IVaultStorage} from "../../../contracts/interfaces/internal/vault/IVaultStorage.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IFarmStrategy} from "../../../contracts/interfaces/internal/strategy/farming/IFarmStrategy.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {IGroomableManager} from "../../../contracts/interfaces/internal/vault/extensions/groomable/IGroomableManager.sol";

contract VaultGroomableTest is VaultTestSuite {
    function test_RebalanceBorrowNoDebtPosition() public {
        deposit(address(this));
        vault.rebalance();

        // ---- Expects ----
        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
        uint256 rebalanceAmount = (lenderStrategy.convertToBase(
            DEPOSIT,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * vault.targetThreshold()) / 1e18;
        assertEq(vault.debtToken().balanceOf(address(vault)), rebalanceAmount);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy()), rebalanceAmount);
        assertEq(lenderStrategy.borrowBalance(), rebalanceAmount);
    }

    function test_RebalanceBorrowWithDebtPosition() public {
        depositAndBorrow(address(this));
        vault.rebalance();

        // ---- Expects ----
        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
        uint256 rebalanceAmount = (lenderStrategy.convertToBase(
            DEPOSIT,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * vault.targetThreshold()) /
            1e18 -
            BORROW;

        assertEq(vault.debtToken().balanceOf(address(vault)), rebalanceAmount);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy()), rebalanceAmount);
        assertEq(lenderStrategy.borrowBalance(), BORROW + rebalanceAmount);
    }

    function test_RebalanceRepay() public {
        deposit(address(this));
        vault.rebalance();

        // Simulate the need to repay
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(5e17, 5e17, 5e17)
        );
        vault.rebalance();

        // ---- Expects ----
        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        uint256 rebalanceAmount = (lenderStrategy.convertToBase(
            DEPOSIT,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * vault.targetThreshold()) / 1e18;

        assertEq(vault.debtToken().balanceOf(address(vault)), rebalanceAmount);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy()), rebalanceAmount);
        assertEq(lenderStrategy.borrowBalance(), rebalanceAmount);
    }

    function test_RebalanceRepayNotEnough() public {
        deposit(address(this));
        vault.rebalance();

        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
        uint256 rebalanceAmount = (lenderStrategy.convertToBase(
            DEPOSIT,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * vault.targetThreshold()) / 1e18;

        // Simulate farm loss
        burnToken(
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy())
        );

        // Simulate the need to repay
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(0, 0, 0)
        );
        vault.rebalance();

        // ---- Expects ----
        assertEq(vault.debtToken().balanceOf(address(vault)), rebalanceAmount);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy()), 0);
        assertEq(lenderStrategy.borrowBalance(), rebalanceAmount);
    }

    // That is to not touch any possible rewards on repayment
    function test_RebalanceRepayUpToVaultBalance() public {
        deposit(address(this));
        vault.rebalance();

        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
        uint256 rebalanceAmount = (lenderStrategy.convertToBase(
            DEPOSIT,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * vault.targetThreshold()) / 1e18;

        // Decrease vault balance [BURN does not work, as the totalSupply is not a storage variable ]
        transferToken(
            address(vault.debtToken()),
            address(vault),
            address(0),
            vault.debtToken().balanceOf(address(vault))
        );

        // Simulate the need to repay
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(0, 0, 0)
        );
        vault.rebalance();

        // ---- Expects ----
        assertEq(vault.debtToken().balanceOf(address(vault)), 0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(vault.activeFarmStrategy()), rebalanceAmount);
        assertEq(lenderStrategy.borrowBalance(), rebalanceAmount);
    }

    function test_RebalanceBorrowWithNoAvailableLiquidity() public {
        deposit(address(this));

        // Simulate lower available liquidity
        vm.mockCall(
            vault.activeLenderStrategy(),
            abi.encodeWithSelector(ILenderStrategy.availableBorrowLiquidity.selector),
            abi.encode(BORROW)
        );
        vault.rebalance();
        assertEq(vault.debtToken().balanceOf(address(vault)), BORROW);
        assertEq(ILenderStrategy(vault.activeLenderStrategy()).borrowBalance(), BORROW);
    }

    function test_MigrateFarmDispatcher() public {
        IFarmDispatcher oldFarmDispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(
            vault.borrowUnderlying(),
            address(oldFarmDispatcher),
            address(oldFarmDispatcher)
        );
        oldFarmDispatcher.addStrategy(newStrategy1, type(uint256).max, address(0));

        deposit(address(this));
        vault.rebalance();

        uint256 oldBalance = oldFarmDispatcher.balance();

        address newFarmDispatcher = makeAddr("newFarmDispatcher");
        vm.mockCall(newFarmDispatcher, abi.encodeWithSelector(IFarmDispatcher.dispatch.selector), abi.encode());
        vaultRegistry.changeVaultFarmDispatcher(deployer.supplyAsset(), deployer.borrowAsset(), newFarmDispatcher);

        assertEq(oldFarmDispatcher.balance(), 0);
        assertEq(IToken(vault.borrowUnderlying()).balanceOf(newFarmDispatcher), oldBalance);
        assertEq(vault.activeFarmStrategy(), newFarmDispatcher);
    }

    function test_MigrateFarmDispatcherNonEmpty() public {
        IFarmDispatcher oldFarmDispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(
            vault.borrowUnderlying(),
            address(oldFarmDispatcher),
            address(oldFarmDispatcher)
        );
        oldFarmDispatcher.addStrategy(newStrategy1, type(uint256).max, address(0));

        deposit(address(this));
        vault.rebalance();

        address newFarmDispatcher = makeAddr("newFarmDispatcher");
        vm.mockCall(newFarmDispatcher, abi.encodeWithSelector(IFarmDispatcher.dispatch.selector), abi.encode());

        vm.mockCall(
            address(oldFarmDispatcher),
            abi.encodeWithSelector(IFarmDispatcher.balance.selector),
            abi.encode(1000)
        );

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IGroomableManager.GR_V1_FARM_DISPATCHER_NOT_EMPTY.selector);
        vaultRegistry.changeVaultFarmDispatcher(supplyAsset, borrowAsset, newFarmDispatcher);
    }

    function test_NoOwnerMigrateFarmDispatcher() public {
        address newFarmDispatcher = makeAddr("newFarmDispatcher");
        vm.expectRevert(IVaultStorage.VS_V1_ONLY_OWNER.selector);
        vault.migrateFarmDispatcher(newFarmDispatcher);
    }

    function test_MigrateFarmDispatcherWithSameStrategy() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        address farmDispatcher = vault.activeFarmStrategy();
        vm.expectRevert(IGroomableManager.GR_V1_FARM_DISPATCHER_ALREADY_ACTIVE.selector);
        vaultRegistry.changeVaultFarmDispatcher(supplyAsset, borrowAsset, farmDispatcher);
    }

    function test_MigrateLender() public {
        deposit(address(this));
        vault.rebalance();

        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
        // Due to the rebalance
        uint256 borrowAmount = (lenderStrategy.convertToBase(DEPOSIT, deployer.supplyAsset(), deployer.borrowAsset()) *
            vault.targetThreshold()) / 1e18;

        ILenderStrategy newLenderStrategy = ILenderStrategy(
            BaseGetter.getBaseLenderStrategy(
                address(vault),
                deployer.supplyAsset(),
                deployer.borrowAsset(),
                vault.activeFarmStrategy(),
                deployer.priceProvider()
            )
        );
        vaultRegistry.changeVaultLendingProvider(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            address(newLenderStrategy)
        );

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(newLenderStrategy.supplyBalance(), DEPOSIT);
        assertEq(newLenderStrategy.borrowBalance(), borrowAmount);

        assertEq(vault.activeLenderStrategy(), address(newLenderStrategy));
        assertEq(vault.supplyToken().activeLenderStrategy(), address(newLenderStrategy));
        assertEq(vault.debtToken().activeLenderStrategy(), address(newLenderStrategy));
    }

    function test_MigrateLenderWithHighFee() public {
        deposit(address(this));
        vault.rebalance();

        // Set flashloan fee for the test to pass
        (, address flashLoanStrategy, ) = vault.getGroomableConfig();
        BaseFlashLoanStrategy(flashLoanStrategy).setFee(1e18); // 100% fee

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );
        vm.expectRevert(IGroomableManager.GR_V1_MIGRATION_FEE_TOO_HIGH.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, newLenderStrategy);
    }

    function test_MigrateLenderWithNoSupply() public {
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );

        vaultRegistry.changeVaultLendingProvider(deployer.supplyAsset(), deployer.borrowAsset(), newLenderStrategy);

        assertEq(vault.activeLenderStrategy(), newLenderStrategy);
    }

    function test_MigrateLenderWithNoDebt() public {
        deposit(address(this));
        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        ILenderStrategy newLenderStrategy = ILenderStrategy(
            BaseGetter.getBaseLenderStrategy(
                address(vault),
                deployer.supplyAsset(),
                deployer.borrowAsset(),
                vault.activeFarmStrategy(),
                deployer.priceProvider()
            )
        );
        vaultRegistry.changeVaultLendingProvider(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            address(newLenderStrategy)
        );

        assertEq(lenderStrategy.supplyBalance(), 0, "Old lender supply zero");
        assertEq(lenderStrategy.borrowBalance(), 0, "Old lender borrow zero");
        assertEq(newLenderStrategy.supplyBalance(), DEPOSIT, "New lender supply");
        assertEq(newLenderStrategy.borrowBalance(), 0, "New lender borrow");

        assertEq(vault.activeLenderStrategy(), address(newLenderStrategy), "New lender is the active strategy");
        assertEq(
            vault.supplyToken().activeLenderStrategy(),
            address(newLenderStrategy),
            "New lender set on the supply token"
        );
        assertEq(
            vault.debtToken().activeLenderStrategy(),
            address(newLenderStrategy),
            "New lender set on the borrow token"
        );
    }

    function test_NoOwnerMigrateLender() public {
        vm.expectRevert(IVaultStorage.VS_V1_ONLY_OWNER.selector);
        vault.migrateLender(address(0));
    }

    function test_MigrateLenderWithSameStrategy() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        address lenderStrategy = vault.activeLenderStrategy();
        vm.expectRevert(IGroomableManager.GR_V1_LENDER_STRATEGY_ALREADY_ACTIVE.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, lenderStrategy);
    }

    function test_MigrateLenderWithRemainingSupply() public {
        deposit(address(this));

        // Simulate remaining supply
        address lenderStrategy = vault.activeLenderStrategy();
        vm.mockCall(
            lenderStrategy,
            abi.encodeWithSelector(ILenderStrategy.supplyBalance.selector),
            abi.encode(DEPOSIT)
        );

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            supplyAsset,
            borrowAsset,
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );
        vm.expectRevert(IGroomableManager.GR_V1_MIGRATION_OLD_SUPPLY_ERROR.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, newLenderStrategy);
    }

    function test_MigrateLenderWithRemainingDebt() public {
        depositAndBorrow(address(this));

        // Simulate remaining supply
        address lenderStrategy = vault.activeLenderStrategy();
        vm.mockCall(lenderStrategy, abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector), abi.encode(BORROW));

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            supplyAsset,
            borrowAsset,
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );

        vm.expectRevert(IGroomableManager.GR_V1_MIGRATION_OLD_BORROW_ERROR.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, newLenderStrategy);
    }

    function test_MigrateLenderWithSupplyResultingInZero() public {
        deposit(address(this));
        vault.rebalance();

        // Simulate zero supply
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );

        vm.mockCall(newLenderStrategy, abi.encodeWithSelector(ILenderStrategy.supplyBalance.selector), abi.encode(0));

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IGroomableManager.GR_V1_MIGRATION_NEW_SUPPLY_ERROR.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, newLenderStrategy);
    }

    function test_MigrateLenderWithDebtResultingInZero() public {
        deposit(address(this));
        vault.rebalance();

        // Simulate zero supply
        address newLenderStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );

        vm.mockCall(newLenderStrategy, abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector), abi.encode(0));

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IGroomableManager.GR_V1_MIGRATION_NEW_BORROW_ERROR.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, newLenderStrategy);
    }

    function test_MigrateLenderTroughFlashloanCallback() public {
        deposit(address(this));
        vault.rebalance();

        vm.expectRevert(IGroomableManager.GR_V1_NOT_FLASH_LOAN_STRATEGY.selector);
        vault.flashLoanCallback(abi.encode(address(0), 0), 0);
    }

    function test_MigrateLenderWhenLiquidated() public {
        ILenderStrategy lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        address userAlice = makeAddr("userAlice");
        address userBob = makeAddr("userBob");
        depositAndBorrow(userAlice); // 10, 5
        depositAndBorrow(userBob); // 20, 10
        depositAndBorrow(userBob);
        vault.rebalance();

        console.log("- Before Liquidation -");
        console.log(
            "Alice: %d supply, %d borrow",
            vault.supplyToken().balanceOf(userAlice),
            vault.debtToken().balanceOf(userAlice)
        );
        console.log(
            "Bob: %d supply, %d borrow",
            vault.supplyToken().balanceOf(userBob),
            vault.debtToken().balanceOf(userBob)
        );
        console.log("Vault: %d borrow", vault.debtToken().balanceOf(address(vault)));
        console.log("Lender: %d supply, %d borrow", lenderStrategy.supplyBalance(), lenderStrategy.borrowBalance());

        simulateSupplyLoss(50, 50, 1);
        assertEq(lenderStrategy.hasSupplyLoss(), true);

        console.log("- Liquidation 50% supply, 50% borrow, 1% fee (supply) -");
        console.log("Lender: %d supply, %d borrow", lenderStrategy.supplyBalance(), lenderStrategy.borrowBalance());

        uint256 oldBorrow = lenderStrategy.borrowBalance();
        uint256 oldSupply = lenderStrategy.supplyBalance();

        ILenderStrategy newLenderStrategy = ILenderStrategy(
            BaseGetter.getBaseLenderStrategy(
                address(vault),
                deployer.supplyAsset(),
                deployer.borrowAsset(),
                vault.activeFarmStrategy(),
                deployer.priceProvider()
            )
        );

        uint256 feeFlashloan = 1e6;
        {
            (, address flashLoanStrategy, ) = vault.getGroomableConfig();
            BaseFlashLoanStrategy(flashLoanStrategy).setFee(feeFlashloan);
        }

        vaultRegistry.changeVaultLendingProvider(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            address(newLenderStrategy)
        );

        console.log("- Lender migrated, 1 flashloan fee (borrow) -");
        console.log(
            "Lender: %d supply, %d borrow",
            newLenderStrategy.supplyBalance(),
            newLenderStrategy.borrowBalance()
        );

        assertEq(newLenderStrategy.hasSupplyLoss(), true);

        assertEq(lenderStrategy.supplyBalance(), 0);
        assertEq(lenderStrategy.borrowBalance(), 0);
        assertEq(newLenderStrategy.supplyBalance(), oldSupply);
        assertEq(newLenderStrategy.borrowBalance(), oldBorrow + feeFlashloan);

        assertEq(vault.activeLenderStrategy(), address(newLenderStrategy));
        assertEq(vault.supplyToken().activeLenderStrategy(), address(newLenderStrategy));
        assertEq(vault.debtToken().activeLenderStrategy(), address(newLenderStrategy));

        vault.snapshotSupplyLoss();

        uint256 aliceSupplyAfter = vault.supplyToken().balanceOf(userAlice);
        uint256 aliceDebtAfter = vault.debtToken().balanceOf(userAlice);
        uint256 bobSupplyAfter = vault.supplyToken().balanceOf(userBob);
        uint256 bobDebtAfter = vault.debtToken().balanceOf(userBob);
        uint256 vaultDebtAfter = vault.debtToken().balanceOf(address(vault));

        console.log("- Liquidation snapshotted -");
        console.log(
            "Alice: %d supply, %d borrow",
            vault.supplyToken().balanceOf(userAlice),
            vault.debtToken().balanceOf(userAlice)
        );
        console.log(
            "Bob: %d supply, %d borrow",
            vault.supplyToken().balanceOf(userBob),
            vault.debtToken().balanceOf(userBob)
        );
        console.log("Vault: %d borrow", vault.debtToken().balanceOf(address(vault)));
        console.log(
            "Lender: %d supply, %d borrow",
            newLenderStrategy.supplyBalance(),
            newLenderStrategy.borrowBalance()
        );

        assertEq(aliceSupplyAfter * 2, bobSupplyAfter);

        assertEq(newLenderStrategy.supplyBalance(), aliceSupplyAfter + bobSupplyAfter);
        assertApproxEqAbs(newLenderStrategy.borrowBalance(), aliceDebtAfter + bobDebtAfter + vaultDebtAfter, 1);

        vault.rebalance();
        vaultDebtAfter = vault.debtToken().balanceOf(address(vault));
        assertApproxEqAbs(newLenderStrategy.borrowBalance(), aliceDebtAfter + bobDebtAfter + vaultDebtAfter, 1);
    }
}
