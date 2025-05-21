// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";
import {BaseSwapStrategy} from "../../base/BaseSwapStrategy.sol";
import {BaseLenderStrategy} from "../../base/BaseLenderStrategy.sol";

import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";
import {SupplyLossTypes} from "../../../contracts/libraries/types/SupplyLossTypes.sol";

import {IIngress} from "../../../contracts/interfaces/internal/access/IIngress.sol";
import {IInterestToken} from "../../../contracts/interfaces/internal/tokens/IInterestToken.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {ISupplyLossManager} from "../../../contracts/interfaces/internal/vault/extensions/supply-loss/ISupplyLossManager.sol";

contract VaultSupplyLossTest is VaultTestSuite {
    IFarmDispatcher dispatcher;
    ILenderStrategy lenderStrategy;

    struct SnapshotData {
        uint256 depositFeePerc;
        uint256 swapFeePerc;
        uint256 depositRewards;
        uint256 liquidationBonus;
        uint256 shortage;
        uint256 supplyLoss;
        uint256 borrowLoss;
        uint256 vaultBalance;
        uint256 totalBorrow;
    }

    function setUp() public override {
        super.setUp();

        dispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
    }

    function test_SnapshotWhenNoSupplyLoss() public {
        assertEq(vault.totalSnapshots(), 0); // initial harvest
        vault.snapshotSupplyLoss();
        assertEq(vault.totalSnapshots(), 0);
    }

    function test_SupplyLossSnapshot() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vm.expectEmit(address(vault));
        emit ISupplyLossManager.SupplyLossSnapshot(0);
        vault.snapshotSupplyLoss();

        _validateState(data);

        assertEq(dispatcher.balance(), 0);
    }

    function test_InterestHasRepaidDebtLoss() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = 0;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% supply loss, 0 borrow loss
        simulateSupplyLoss(50, 0, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_WithdrawFromFarmWithShortage() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 shortage = vaultBalance / 2;

        SnapshotData memory data = SnapshotData(
            0,
            0,
            0,
            0,
            shortage,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // Simulate shortage(farm loss) -> 50%
        burnToken(deployer.borrowAsset(), address(dispatcher), shortage);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);

        assertEq(dispatcher.balance(), 0);
    }

    // 100% shortage
    function test_WithdrawFromFarmWith100Shortage() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 shortage = vaultBalance;

        SnapshotData memory data = SnapshotData(
            0,
            0,
            0,
            0,
            shortage,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // Simulate shortage(farm loss) -> 100%
        burnToken(deployer.borrowAsset(), address(dispatcher), shortage);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_WithdrawFromFarmUpToVaultBalance() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate farm to have more funds than the vault balance
        mintToken(deployer.borrowAsset(), address(dispatcher), BORROW);

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);

        assertEq(dispatcher.balance(), BORROW); // the remaining part we have simulated
    }

    function test_InjectionFeeDueToSwap() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate swap fee
        BaseSwapStrategy(vault.swapStrategy()).setSwapInFee(10); // 10%

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 injectionFeePerc = 10;

        SnapshotData memory data = SnapshotData(
            injectionFeePerc,
            0,
            0,
            0,
            0,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_InjectionFeeDueToDeposit() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate deposit fee
        BaseLenderStrategy(address(lenderStrategy)).setDepositFee(10); // 10%

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 injectionFeePerc = 10;

        SnapshotData memory data = SnapshotData(
            injectionFeePerc,
            0,
            0,
            0,
            0,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_InjectionFeeNotFullyCovered() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate deposit rewards
        uint256 profit = 5e16;
        BaseLenderStrategy(address(lenderStrategy)).setDepositRewards(profit);

        // Simulate swap fee
        BaseSwapStrategy(vault.swapStrategy()).setSwapInFee(10); // 10%

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 injectionFeePerc = 10; // 10%

        SnapshotData memory data = SnapshotData(
            0,
            injectionFeePerc,
            profit,
            0,
            0,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    // When the balance received is bigger than the one deposited
    function test_ProfitPartiallyCoveredLoss() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate deposit rewards
        uint256 profit = 1e18;
        BaseLenderStrategy(address(lenderStrategy)).setDepositRewards(profit);

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, profit, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_ProfitFullyCoveredLoss() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate deposit rewards to cover the entire loss
        uint256 profit = DEPOSIT;
        BaseLenderStrategy(address(lenderStrategy)).setDepositRewards(profit);

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, profit, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    // Vault balance greater than total balance (rounding)
    function test_VaultBalanceGTTotalBalance() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // Simulate vault balance greater than total balance
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IInterestToken.balanceStored.selector, address(vault)),
            abi.encode(vaultBalance + 1) // 1 wei rounding
        );

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // Revert back the mock call
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IInterestToken.balanceStored.selector, address(vault)),
            abi.encode(0)
        );
        _validateState(data);
    }

    function test_SupplyLossWhenNoFarming() public {
        address user = vm.addr(1);
        depositAndBorrow(user);

        uint256 vaultBalance = 0;
        uint256 totalBorrow = BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    // Supply loss is due to a vault being liquidated into the lender provider
    // The liquidator receives a bonus for keeping the protocol healthy
    function test_LiquidationBonus() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance + BORROW;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;
        uint256 liquidationBonus = DEPOSIT / 100; // 1%

        SnapshotData memory data = SnapshotData(
            0,
            0,
            0,
            liquidationBonus,
            0,
            supplyLoss,
            borrowLoss,
            vaultBalance,
            totalBorrow
        );

        // 50% loss, 1% bonus fee
        simulateSupplyLoss(50, 50, 1);
        vault.snapshotSupplyLoss();
        _validateState(data);
    }

    function test_RepayWithExcessBalance() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 totalBorrow = vaultBalance;

        uint256 supplyLoss = DEPOSIT / 2;
        uint256 borrowLoss = totalBorrow / 2;

        SnapshotData memory data = SnapshotData(0, 0, 0, 0, 0, supplyLoss, borrowLoss, vaultBalance, totalBorrow);

        // Simulate excess balance
        vm.mockCall(
            address(lenderStrategy),
            abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector),
            abi.encode(vaultBalance / 2 - 1)
        );

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // Revert back the mock call
        vm.mockCall(
            address(lenderStrategy),
            abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector),
            abi.encode(0)
        );
        _validateState(data);
    }

    function _validateState(SnapshotData memory data) internal {
        // Check global state
        CommonTypes.SnapshotType memory snapshot = vault.getSnapshot(0);
        assertEq(snapshot.kind, 1);
        assertEq(snapshot.supplyIndex, vault.supplyToken().interestIndex());
        assertEq(snapshot.borrowIndex, vault.debtToken().interestIndex());

        assertEq(vault.totalSnapshots(), 1);
        assertEq(vault.userSnapshots(address(vault)), 1); // has been committed
        assertEq(IIngress(vault.ingressControl()).pause(), true);

        // Check balances
        uint256 withdrawn = data.vaultBalance - data.shortage;
        uint256 vaultWindfall = (data.vaultBalance * data.borrowLoss) / data.totalBorrow;

        if (vaultWindfall > withdrawn) {
            vaultWindfall = withdrawn;
        }

        uint256 swapFeeInBorrow = (vaultWindfall * data.swapFeePerc) / 100;
        uint256 redepositedAmount = lenderStrategy.convertToBase(
            vaultWindfall - swapFeeInBorrow,
            deployer.borrowAsset(),
            deployer.supplyAsset()
        );

        uint256 depositFee = (redepositedAmount * data.depositFeePerc) / 100;
        redepositedAmount -= depositFee;

        uint256 depositFeeInBorrow = lenderStrategy.convertToBase(
            depositFee,
            deployer.supplyAsset(),
            deployer.borrowAsset()
        );
        uint256 injectionFeeSupply = lenderStrategy.convertToBase(
            swapFeeInBorrow + depositFeeInBorrow,
            deployer.borrowAsset(),
            deployer.supplyAsset()
        );

        if (injectionFeeSupply >= data.depositRewards) {
            injectionFeeSupply -= data.depositRewards;
        } else {
            redepositedAmount += data.depositRewards - injectionFeeSupply;
            injectionFeeSupply = 0;
            data.depositRewards = 0;
        }

        if (redepositedAmount > data.supplyLoss) {
            assertEq(lenderStrategy.supplyBalance(), DEPOSIT + (redepositedAmount - data.supplyLoss));
        } else {
            // Rewards are used to repay for part of the fee
            if (data.depositRewards > 0) {
                assertEq(
                    lenderStrategy.supplyBalance(),
                    DEPOSIT - data.supplyLoss + injectionFeeSupply + redepositedAmount - data.liquidationBonus
                );
            } else {
                assertEq(
                    lenderStrategy.supplyBalance(),
                    DEPOSIT - data.supplyLoss + redepositedAmount - data.liquidationBonus
                );
            }
        }

        uint256 repaidAmount = (data.vaultBalance - data.shortage) - vaultWindfall;
        assertEq(lenderStrategy.borrowBalance(), data.totalBorrow - data.borrowLoss - repaidAmount);

        assertEq(vault.debtToken().balanceStored(address(vault)), 0);

        // Check snapshot data
        SupplyLossTypes.SupplyLoss memory lossSnapshot = vault.getSupplyLossSnapshot(0);

        assertEq(lossSnapshot.borrowLossAtSnapshot, data.borrowLoss - vaultWindfall);
        assertEq(lossSnapshot.supplyBalanceAtSnapshot, DEPOSIT);
        assertEq(lossSnapshot.borrowBalanceAtSnapshot, data.totalBorrow - (data.vaultBalance - data.shortage));
        assertEq(lossSnapshot.withdrawShortage, data.shortage);

        // Check if vault is the only borrower as the loss is considered a fee
        uint256 supplyFee = lossSnapshot.borrowBalanceAtSnapshot == 0 ? data.supplyLoss - redepositedAmount : 0;
        assertEq(lossSnapshot.fee, injectionFeeSupply + data.liquidationBonus + supplyFee);

        // Check if profit has covered the entire loss
        if (redepositedAmount > data.supplyLoss) {
            assertEq(lossSnapshot.supplyLossProfit, redepositedAmount - data.supplyLoss);
            assertEq(lossSnapshot.supplyLossAtSnapshot, 0);
        } else {
            assertEq(lossSnapshot.supplyLossProfit, 0);
            // Liquidation bonus has already been subtracted from the supply loss in the lender strategy
            assertEq(
                lossSnapshot.supplyLossAtSnapshot,
                data.supplyLoss - (redepositedAmount + injectionFeeSupply + supplyFee)
            );
        }
    }
}
