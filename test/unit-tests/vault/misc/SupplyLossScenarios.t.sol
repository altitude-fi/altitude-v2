// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../../utils/VaultTestSuite.sol";

import {BaseGetter} from "../../../base/BaseGetter.sol";

import {VaultTypes} from "../../../../contracts/libraries/types/VaultTypes.sol";
import {HarvestTypes} from "../../../../contracts/libraries/types/HarvestTypes.sol";

import {IVaultCoreV1} from "../../../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {IIngress} from "../../../../contracts/interfaces/internal/access/IIngress.sol";
import {ISwapStrategy} from "../../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {IFarmDispatcher} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {ILenderStrategy} from "../../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";

contract SupplyLossScenariosTests is VaultTestSuite {
    // Price is 1 ETH = 2000 USDC
    uint256 public constant DEPOSIT_BIG = 10e18; // 10 ETH
    uint256 public constant BORROW_BIG = 14000e6; // 14_000 USDC

    uint256 public constant DEPOSIT_MID = 5e18; // 5 ETH
    uint256 public constant BORROW_MID = 7000e6; // 7_000 USDC

    uint256 public constant DEPOSIT_SMALL = 1e18; // 1 ETH

    IFarmDispatcher dispatcher;
    ILenderStrategy lenderStrategy;

    function setUp() public override {
        super.setUp();

        dispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 2000e6); // 1 ETH = 2000 USDC
    }

    function _genUsers(uint256 numberOfUsers) internal pure returns (address[] memory) {
        address[] memory users = new address[](numberOfUsers);
        for (uint256 i = 1; i < numberOfUsers + 1; i++) {
            users[i - 1] = vm.addr(i);
        }
        return users;
    }

    function _validateState(address[] memory users) internal view {
        _validateState(users, 100);
    }

    // Supply error tolerance is due to rounding issues
    function _validateState(address[] memory users, uint256 errorTolerance) internal view {
        uint256 usersDeposit;
        uint256 usersBorrow;
        for (uint256 i = 0; i < users.length; i++) {
            usersDeposit += vault.supplyToken().balanceOf(users[i]);
            usersBorrow += vault.debtToken().balanceOf(users[i]);
        }

        usersBorrow += vault.debtToken().balanceOf(address(vault));

        assertApproxEqAbs(usersDeposit, lenderStrategy.supplyBalance(), errorTolerance);
        assertApproxEqAbs(usersBorrow, lenderStrategy.borrowBalance(), errorTolerance);
    }

    function _updateUsers(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            vault.updatePosition(users[i]);
        }
    }

    function test_BalanceWithNoRebalanceNoCommit() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], DEPOSIT_SMALL);

        simulateSupplyLoss(47, 50, 0);
        vault.snapshotSupplyLoss();

        _validateState(users);
    }

    function test_BalanceWithRebalanceNoCommit() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], 1e15);

        vault.rebalance();
        snapshotSupply_50_Loss(1500e6);

        _validateState(users);
    }

    function test_LossDistributionNoRebalance() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);

        snapshotSupply_50_Loss(2000e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_LossDistributionWithRebalance() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);

        vault.rebalance();
        snapshotSupply_50_Loss(1500e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_SupplyLossWithFarmDeficit() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);

        vault.rebalance();

        // Simulate deficit(farm loss) -> 25%
        burnToken(deployer.borrowAsset(), address(dispatcher), dispatcher.balance() / 4);

        snapshotSupply_50_Loss(1500e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_BothBalancesEqualBeforeAndAfterCommitNoRebalance() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], DEPOSIT_SMALL);

        snapshotSupply_50_Loss(2000e6);

        uint256 user1BalanceBefore = vault.supplyToken().balanceOf(users[0]);
        vault.updatePosition(users[0]);
        uint256 user1BalanceAfter = vault.supplyToken().balanceStored(users[0]);

        uint256 user2BalanceBefore = vault.supplyToken().balanceOf(users[1]);
        vault.updatePosition(users[1]);
        uint256 user2BalanceAfter = vault.supplyToken().balanceStored(users[1]);

        uint256 user3BalanceBefore = vault.supplyToken().balanceOf(users[2]);
        vault.updatePosition(users[2]);
        uint256 user3BalanceAfter = vault.supplyToken().balanceStored(users[2]);

        assertEq(user1BalanceBefore, user1BalanceAfter);
        assertEq(user2BalanceBefore, user2BalanceAfter);
        assertEq(user3BalanceBefore, user3BalanceAfter);

        _validateState(users);
    }

    function test_BothBalancesEqualBeforeAndAfterCommitWithRebalance() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], DEPOSIT_SMALL);

        vault.rebalance();

        snapshotSupply_50_Loss(1500e6);

        uint256 user1BalanceBefore = vault.supplyToken().balanceOf(users[0]);
        uint256 user2BalanceBefore = vault.supplyToken().balanceOf(users[1]);
        uint256 user3BalanceBefore = vault.supplyToken().balanceOf(users[2]);

        _updateUsers(users);

        uint256 user1BalanceAfter = vault.supplyToken().balanceStored(users[0]);
        uint256 user2BalanceAfter = vault.supplyToken().balanceStored(users[1]);
        uint256 user3BalanceAfter = vault.supplyToken().balanceStored(users[2]);

        assertEq(user1BalanceBefore, user1BalanceAfter);
        assertEq(user2BalanceBefore, user2BalanceAfter);
        assertEq(user3BalanceBefore, user3BalanceAfter);

        _validateState(users);
    }

    // Test users coming after supply loss should not have impact
    function test_UsersEnterAfterSupplyLossShouldNotParticipate() public {
        IIngress(vault.ingressControl()).setDepositLimits(0, 100e18, 100e18);

        address[] memory users = _genUsers(5);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], 1e15);
        vault.rebalance();

        snapshotSupply_50_Loss(1500e6);

        deposit(users[3], DEPOSIT_BIG);
        depositAndBorrow(users[4], 13e18, 13640e6);

        _updateUsers(users);

        assertEq(vault.supplyToken().balanceOf(users[3]), DEPOSIT_BIG);
        assertEq(vault.supplyToken().balanceOf(users[4]), 13e18);

        _validateState(users);
    }

    function test_SupplyLossAndInterestAccumulationNoRebalance() public {
        address[] memory users = _genUsers(4);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], 1e15);

        simulateSupplyLoss(50, 50, 0);

        // Simulate interest accumulation
        accumulateInterest(1e9, 1e3);

        vault.snapshotSupplyLoss();

        deposit(users[3], DEPOSIT_BIG);

        _validateState(users);
    }

    function test_SupplyLossAndInterestAccumulationWithRebalance() public {
        address[] memory users = _genUsers(4);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], DEPOSIT_SMALL);

        vault.rebalance();

        simulateSupplyLoss(50, 50, 0);
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1500e6); // 1 ETH = 1500 USDC

        // Simulate interest accumulation
        accumulateInterest(1e9, 1e3);

        vault.snapshotSupplyLoss();

        deposit(users[3], DEPOSIT_BIG);

        _validateState(users);
    }

    function test_UserEntersAfterRebalanceParticipateInSupplyLoss() public {
        address[] memory users = _genUsers(4);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        deposit(users[1], DEPOSIT_MID);

        vault.rebalance();

        deposit(users[2], DEPOSIT_SMALL);
        snapshotSupply_50_Loss(1500e6);

        deposit(users[3], DEPOSIT_BIG);

        _validateState(users);
    }

    // A stable user is one with supply only and no borrow
    function test_StableUsersOnly() public {
        address[] memory users = _genUsers(4);
        deposit(users[0], DEPOSIT_BIG);
        deposit(users[1], 71235e14); // 7.1235
        deposit(users[2], 4341e13); // 0.4341

        vault.rebalance();
        snapshotSupply_50_Loss(1500e6);

        deposit(users[3], 223592e13); // 2.23592

        _updateUsers(users);
        _validateState(users);
    }

    // Check with bigger amounts if the distribution gap will become bigger (should not)
    function test_BigNumberLossDistribution() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG * 100, BORROW_BIG * 100);
        depositAndBorrow(users[1], 5917e18, 8283800e6);
        deposit(users[2], 3017e18);

        vault.rebalance();
        snapshotSupply_50_Loss(1500e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test rewards distribution in case of multiple supply losses with all the money being utilized to farming
    function test_MultipleSupplyLossesFullInFarm() public {
        address[] memory users = _genUsers(6);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], 1e15);

        vault.rebalance();
        snapshotSupply_50_Loss(1500e6);

        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        depositAndBorrow(users[3], DEPOSIT_BIG, 10499e6);
        depositAndBorrow(users[4], 13e18, 13640e6);

        vault.rebalance();

        snapshotSupply_50_Loss(1400e6);

        deposit(users[5], DEPOSIT_BIG);

        _updateUsers(users);
        _validateState(users);
    }

    // Test rewards distribution in case of multiple supply losses with not all the money being utilized to farming
    function test_MultipleSupplyLossesPartiallyInFarm() public {
        address[] memory users = _genUsers(6);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_MID, BORROW_MID);
        deposit(users[2], DEPOSIT_SMALL);

        snapshotSupply_50_Loss(1500e6);

        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        depositAndBorrow(users[3], DEPOSIT_BIG, 10499e6);
        depositAndBorrow(users[4], 13e18, 13640e6);

        snapshotSupply_50_Loss(2000e6);

        deposit(users[5], DEPOSIT_BIG);

        _updateUsers(users);
        _validateState(users);
    }

    function test_DifferentTokenDecimals() public {
        deployer = new TestDeployer();
        deployer.initDeployer(address(deployer), address(this));

        address supplyToken = BaseGetter.getBaseERC20(8); // wBTC
        address borrowToken = BaseGetter.getBaseERC20(18); // DAI

        // Simulate different decimals
        deployer.setTokens(supplyToken, borrowToken);

        vaultRegistry = deployer.deployDefaultProtocol();
        vault = deployer.deployDefaultVault(vaultRegistry);
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        setBorrowLimits(55e16, 55e16, 55e16); // 55%

        setPrice(supplyToken, borrowToken, 2000e18); // 1 wBTC = 2000 DAI

        // ------------ End Preparation ------------

        address[] memory users = _genUsers(6);
        depositAndBorrow(users[0], 10e8, 7000e18);
        depositAndBorrow(users[1], 5e8, 5500e18);
        deposit(users[2], 1e5);
        vault.rebalance();

        snapshotSupply_50_Loss(1500e18);

        // Increase limits
        setBorrowLimits(69e16, 69e16, 69e16); // 69%
        depositAndBorrow(users[3], 10e8, 10300e18);
        depositAndBorrow(users[4], 13e8, 13440e18);
        vault.rebalance();

        snapshotSupply_50_Loss(1000e18);

        deposit(users[5], 10e8);

        _updateUsers(users);
        _validateState(users);
    }

    function test_UserBorrowsBeforeAndAfterSupplyLoss() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 8000e6);
        depositAndBorrow(users[1], DEPOSIT_MID, 3500e6);
        vault.rebalance();

        snapshotSupply_50_Loss(1500e6);

        // Available borrow is limited due to the liquidation
        // Maximum available is = 2.717(after liq) deposit * 1.5 price * 0.7 limit = 2853 (1750 has been borrowed already)
        // That is why the user can still borrow up to his limit
        vm.prank(users[1]);
        vault.borrow(1103e6);

        _updateUsers(users);
        _validateState(users);
    }

    //  LTV > 100% (with rebalance)
    function test_HighLTV() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        deposit(users[1], DEPOSIT_MID);
        vault.rebalance();

        snapshotSupply_50_Loss(1300e6);
        depositAndBorrow(users[2], DEPOSIT_SMALL, 910e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Оne user is with LTV > 100 after supply loss. The other user can not borrow/withdraw
    function test_HighLTVUserBlockingOthers() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        deposit(users[1], DEPOSIT_MID);
        vault.rebalance();

        snapshotSupply_50_Loss(1500e6);

        vm.prank(users[1]);
        vm.expectRevert(IVaultCoreV1.VC_V1_FARM_WITHDRAW_INSUFFICIENT.selector);
        vault.borrow(5250e6); // borrow up to his 70% limit => 5(deposit) * 1.5(price) * 0.7(limit) = 5.25

        vm.prank(users[1]);
        vm.expectRevert(IVaultCoreV1.VC_V1_UNHEALTHY_VAULT_RISK.selector);
        vault.withdraw(DEPOSIT_MID, users[1]);

        _validateState(users);
    }

    function test_RebalanceBorrowInSupplyLoss() public {
        IIngress(vault.ingressControl()).setDepositLimits(0, 100e18, 100e18);

        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 16479e6);
        deposit(users[1], DEPOSIT_MID);
        vault.rebalance();

        snapshotSupply_50_Loss(1900e6);
        vault.rebalance();
        depositAndBorrow(users[2], DEPOSIT_MID, 7600e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_LenderMigrationInSupplyLoss() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        deposit(users[1], DEPOSIT_MID);
        vault.rebalance();

        snapshotSupply_50_Loss(1900e6);

        // New lender strategy
        lenderStrategy = ILenderStrategy(
            BaseGetter.getBaseLenderStrategy(
                address(vault),
                deployer.supplyAsset(),
                deployer.borrowAsset(),
                address(dispatcher),
                deployer.priceProvider()
            )
        );

        vaultRegistry.changeVaultLendingProvider(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            address(lenderStrategy)
        );

        depositAndBorrow(users[2], DEPOSIT_MID, 6000e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_UsersLiquidationInSupplyLoss() public {
        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        address[] memory users = _genUsers(4);
        depositAndBorrow(users[0], DEPOSIT_BIG, 16479e6);
        depositAndBorrow(users[1], DEPOSIT_MID, 8240e6);
        vault.rebalance();

        snapshotSupply_50_Loss(1800e6);

        // Perform liquidation
        uint256 liquidationAmount = vault.debtToken().balanceOf(users[0]) + vault.debtToken().balanceOf(users[1]);
        mintToken(deployer.borrowAsset(), address(this), liquidationAmount);
        IToken(deployer.borrowAsset()).approve(address(vault), liquidationAmount);
        vault.liquidateUsers(users, liquidationAmount);

        // As the contract is the liquidator, it receives tokens as well
        users[3] = address(this);
        _validateState(users);
    }

    function test_HarvestRatioChangeDueToSupplyLoss() public {
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1000e6); // 1 ETH = 1000 USDC

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 2000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 3000e6);
        vault.rebalance();

        // 10 deposit * 1 price * 0.7 limit - 2 borrow = 5 active asset => 10 = 100% => 5 = 50%
        uint256 user1AA = (((lenderStrategy.convertToBase(DEPOSIT_BIG, deployer.supplyAsset(), deployer.borrowAsset()) *
            70) / 100) - 2000e6) / 10;

        // 10 deposit * 1 price * 0.7 limit - 3 borrow = 4 active asset => 10 = 100% => 4 = 40%
        uint256 user2AA = (((lenderStrategy.convertToBase(DEPOSIT_BIG, deployer.supplyAsset(), deployer.borrowAsset()) *
            70) / 100) - 3000e6) / 10;

        snapshotSupply_50_Loss(2000e6);
        _updateUsers(users);

        uint256 user1NewAA = (((lenderStrategy.convertToBase(
            vault.supplyToken().balanceOf(users[0]),
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * 70) / 100) - vault.debtToken().balanceOf(users[0])) / 10;

        uint256 user2NewAA = (((lenderStrategy.convertToBase(
            vault.supplyToken().balanceOf(users[1]),
            deployer.supplyAsset(),
            deployer.borrowAsset()
        ) * 70) / 100) - vault.debtToken().balanceOf(users[1])) / 10;

        assertNotEq(user1AA, user1NewAA);
        assertNotEq(user2AA, user2NewAA);
    }

    function test_SupplyLossAndHarvest_Earnings() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 8000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();

        snapshotSupply_50_Loss(1900e6);
        harvestWithRewards();

        _updateUsers(users);
        _validateState(users);
    }

    function test_HarvestAndSupplyLoss_Earnings() public {
        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 16479e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();

        harvestWithRewards();
        snapshotSupply_50_Loss(1900e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test supply loss, then harvest, supply loss (big price drop in between)
    function test_HarvestBetweenTwoSupplyLosses() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 8000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();
        snapshotSupply_50_Loss(1900e6);

        vault.rebalance();
        harvestWithRewards();
        snapshotSupply_50_Loss(1700e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test supply loss in between positive and negative harvests
    function test_SupplyLossBetweenTwoHarvests() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 8000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();
        harvestWithRewards();

        snapshotSupply_50_Loss(1900e6);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 2);

        _updateUsers(users);
        _validateState(users);
    }

    function test_ManySupplyLossesBetweenTwoHarvests() public {
        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 8000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();
        harvestWithRewards();

        snapshotSupply_50_Loss(1900e6);
        vault.rebalance();

        snapshotSupply_50_Loss(1850e6);

        // Perform liquidation
        uint256 liquidationAmount = 10000e6;
        mintToken(deployer.borrowAsset(), address(this), liquidationAmount);
        IToken(deployer.borrowAsset()).approve(address(vault), liquidationAmount);
        vault.liquidateUsers(users, liquidationAmount);

        harvestWithRewards();

        // Liquidation makes the contract participate into the vault
        users[2] = address(this);
        _updateUsers(users);
        _validateState(users);
    }

    // Test one user updates position but the other one skip to the end
    function test_HarvestCommitSupplyLost() public {
        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, 16479e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();
        harvestWithRewards();

        vault.updatePosition(users[0]);
        harvestWithRewards();
        vault.updatePosition(users[0]);

        snapshotSupply_50_Loss(1900e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test if there is a need to store updated balance if one updates position before supply loss
    function test_CommitToSupplyLost() public {
        // Increase limits
        setBorrowLimits(824e15, 824e15, 824e15); // 82.4%

        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 16479e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 4000e6);
        vault.rebalance();
        harvestWithRewards();
        harvestWithRewards();
        vault.updatePosition(users[0]);

        snapshotSupply_50_Loss(1900e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test liquidation at a given price, but the price increases before making a snapshot [NO REBALANCE]
    function test_SupplyLossAtDifferentPricesNoRebalance() public {
        IIngress(vault.ingressControl()).setDepositLimits(0, 100e18, 100e18);

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_BIG, BORROW_MID);

        snapshotSupply_50_Loss(3000e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_SupplyLossAtDifferentPricesWithRebalance() public {
        IIngress(vault.ingressControl()).setDepositLimits(0, 100e18, 100e18);

        address[] memory users = _genUsers(3);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        depositAndBorrow(users[1], DEPOSIT_BIG, BORROW_MID);
        vault.rebalance();

        snapshotSupply_50_Loss(3000e6);

        _updateUsers(users);
        _validateState(users);
    }

    // Test vault liquidation and then all the steps required for unpausing the vault
    function test_SupplyLossAndRecovery() public {
        // 1. Snapshot vault liquidation
        // 2. Repay all bad debt
        // 3. Inject supply
        // 4. Liquidate negative users
        // 5. Run harvest
        // 6. Inject missing uncommitted earnings due to negative users
        // 7. Commit all the users

        IIngress(vault.ingressControl()).setDepositLimits(0, 100e18, 100e18);

        address[] memory users = _genUsers(4);
        depositAndBorrow(users[0], DEPOSIT_BIG, BORROW_BIG);
        vault.rebalance();
        deposit(users[1], DEPOSIT_BIG);
        depositAndBorrow(users[2], DEPOSIT_BIG, 5000e6);

        snapshotSupply_50_Loss(500e6);

        // 2. Repay bad debt
        uint256 badDebt = vault.debtToken().balanceOf(users[0]) * 2;
        mintToken(deployer.borrowAsset(), address(this), badDebt);
        IToken(deployer.borrowAsset()).approve(address(vault), badDebt);
        vault.repayBadDebt(badDebt, users[0]);

        // 3. Inject supply
        uint256 targetTotalSupply = vault.supplyToken().balanceOf(users[1]) + vault.supplyToken().balanceOf(users[2]);
        uint256 amountShortage = targetTotalSupply - lenderStrategy.supplyBalance();
        mintToken(deployer.supplyAsset(), address(this), amountShortage);
        IToken(deployer.supplyAsset()).approve(address(vault), amountShortage);
        vaultRegistry.injectSupplyInVault(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            amountShortage,
            vault.supplyToken().calcNewIndex()
        );

        // 4. Liquidate negative users
        // Reset the user to be for 50% liquidation only
        (address liquidatableManager, , , , ) = vault.getLiquidationConfig();
        vaultRegistry.setLiquidationConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.LiquidatableConfig(liquidatableManager, 5e17, 1e16, 0, 0)
        );
        uint256 liquidationAmount = vault.debtToken().balanceOf(users[2]);
        address[] memory liquidationUsers = new address[](1);
        liquidationUsers[0] = users[2];
        mintToken(deployer.borrowAsset(), address(this), liquidationAmount);
        IToken(deployer.borrowAsset()).approve(address(vault), liquidationAmount);
        vault.liquidateUsers(liquidationUsers, liquidationAmount);

        // 5. Price drop meaning new negative users
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 400e6); // 1 ETH = 400 USDC

        // 6. Emergency harvest
        harvestWithRewards();

        // 7. Inject missing rewards
        uint256 user3DebtNow = vault.debtToken().balanceOf(users[2]);
        uint256 user3SupplyNow = vault.supplyToken().balanceOf(users[2]);
        uint256 negativeActiveAssets = user3DebtNow - (((user3SupplyNow * 400e6) / 1e18) * 8) / 10;

        HarvestTypes.HarvestData memory harvestData = vault.getHarvest(1);

        uint256 user3Costs = (negativeActiveAssets * harvestData.farmEarnings) / harvestData.vaultActiveAssets;

        mintToken(deployer.borrowAsset(), address(this), user3Costs);
        IToken(deployer.borrowAsset()).approve(address(vaultRegistry), user3Costs);
        vaultRegistry.injectBorrowAssetsInVault(deployer.supplyAsset(), deployer.borrowAsset(), user3Costs);

        users[3] = address(this);
        _updateUsers(users);
        _validateState(users);
    }

    // Test farm loss harvest, normal harvest with one positive and one negative users and then supply loss
    function test_LongFlow_1() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 1000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 12000e6);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1450e6); // 1 ETH = 1450 USDC
        harvestWithRewards();
        snapshotSupply_50_Loss(2000e6);

        _updateUsers(users);

        // In this flow 1 wei of farm loss becomes not distributed and it is ~ to 300e6 represented in supply
        // due to the decimals difference
        _validateState(users, 500e6); // supply wei error tolerance
    }

    // Test farm loss harvest, price drop, harvest, supply loss, deposit & borrow, harvest, price drop, harvest, supply loss
    function test_LongFlow_2() public {
        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 1000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 12000e6);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1600e6); // 1 ETH = 1600 USDC
        harvestWithRewards();

        snapshotSupply_50_Loss(2000e6);

        depositAndBorrow(users[1], DEPOSIT_BIG, 6000e6);
        vault.rebalance();
        harvestWithRewards();

        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1000e6); // 1 ETH = 1000 USDC
        harvestWithRewards();
        snapshotSupply_50_Loss(2000e6);

        _updateUsers(users);
        _validateState(users, 1500e6); // supply wei error tolerance
    }

    // Test farm loss harvest, harvest, price drop, liquidation, price increase, farm lost harvest, price drop, harvest, liquidation
    function test_LongFlow_3() public {
        // Increase limits
        setBorrowLimits(8e17, 8e17, 8e17); // 80%

        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 1000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 12000e6);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1600e6); // 1 ETH = 1600 USDC
        harvestWithRewards();

        snapshotSupply_50_Loss(1600e6);
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 2000e6); // 1 ETH = 2000 USDC
        vault.rebalance();

        farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1450e6); // 1 ETH = 1450 USDC
        harvestWithRewards();
        snapshotSupply_50_Loss(1450e6);

        _updateUsers(users);
        _validateState(users);
    }

    function test_LongFlow_3_CommitByChunks() public {
        // Increase limits
        setBorrowLimits(8e17, 8e17, 8e17); // 80%

        address[] memory users = _genUsers(2);
        depositAndBorrow(users[0], DEPOSIT_BIG, 1000e6);
        depositAndBorrow(users[1], DEPOSIT_BIG, 12000e6);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1600e6); // 1 ETH = 1600 USDC
        harvestWithRewards();

        snapshotSupply_50_Loss(1600e6);
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 2000e6); // 1 ETH = 2000 USDC
        vault.rebalance();

        farmBalance = dispatcher.balance();
        harvestWithFarmLoss(farmBalance, farmBalance / 100); // 1% farm loss
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), 1450e6); // 1 ETH = 1450 USDC
        harvestWithRewards();
        snapshotSupply_50_Loss(1450e6);

        vault.updatePositionTo(users[0], 1);
        vault.updatePositionTo(users[0], 2);
        vault.updatePositionTo(users[0], 3);
        vault.updatePositionTo(users[0], 4);
        vault.updatePositionTo(users[0], 5);
        vault.updatePositionTo(users[0], 6);
        vault.updatePositionTo(users[1], 1);
        vault.updatePositionTo(users[1], 2);
        vault.updatePositionTo(users[1], 3);
        vault.updatePositionTo(users[1], 4);
        vault.updatePositionTo(users[1], 5);
        vault.updatePositionTo(users[1], 6);
        _validateState(users);
    }
}
