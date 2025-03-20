pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import "../../utils/VaultTestSuite.sol";
import {BaseLenderStrategy} from "../../base/BaseLenderStrategy.sol";

import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";
import {HarvestTypes} from "../../../contracts/libraries/types/HarvestTypes.sol";
import {SupplyLossTypes} from "../../../contracts/libraries/types/SupplyLossTypes.sol";

import {IIngress} from "../../../contracts/interfaces/internal/access/IIngress.sol";
import {IInterestVault} from "../../../contracts/interfaces/internal/vault/IInterestVault.sol";
import {IVaultStorage} from "../../../contracts/interfaces/internal/vault/IVaultStorage.sol";
import {IInterestVault} from "../../../contracts/interfaces/internal/vault/IInterestVault.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IHarvestableManager} from "../../../contracts/interfaces/internal/vault/extensions/harvestable/IHarvestableManager.sol";

contract VaultSnapshotableTest is VaultTestSuite {
    using stdStorage for StdStorage;

    IFarmDispatcher dispatcher;
    ILenderStrategy lenderStrategy;

    function setUp() public override {
        super.setUp();

        dispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());

        // Remove the factor of reserve
        disableReserveFactor();
    }

    function test_CommitFirstTimeUser() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        address user2 = vm.addr(2);
        deposit(user2);
        assertEq(vault.userSnapshots(user2), 1); // User is up to date
        assertEq(vault.getUserHarvest(user2).harvestId, 1); // User is up to date
    }

    function test_CommitValidation() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        vm.mockCallRevert(
            vault.ingressControl(),
            abi.encodeWithSelector(IIngress.validateCommit.selector),
            "REVERT_MESSAGE"
        );

        vm.expectRevert("REVERT_MESSAGE");
        vault.updatePosition(user);
    }

    // vaultReserveUncommitted is higher than 0 on repayLoan
    // [KNOWN ISSUE] VM.roll breaks the coverage due to --ir-minimum
    function test_CommitHarvestWithReserveFactorAndRewards() public {
        enableReserveFactor();
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        // Simulate vm.roll the hard way to simulate user enters between 2 harvests
        stdstore.target(address(vault)).sig("getUserHarvest(address)").with_key(user).depth(1).checked_write(6);

        stdstore.target(address(vault)).sig("getHarvest(uint256)").with_key(1).depth(9).checked_write(11);

        vault.updatePosition(user);

        assertEq(
            vault.claimableRewards(user),
            (REWARDS - (REWARDS * deployer.RESERVE_FACTOR()) / 1e18) / 2 // User has joined in the middle of the harvest at he should receive only half of his potential rewards
        );
    }

    // Commit harvest with negative active assets
    function test_CommitHarvestWithNAA() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        depositAndBorrow(user2);

        vault.rebalance();

        // Simulate negative user
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(4e17, 4e17, 4e17)
        );

        harvestWithRewards();

        // Inject rewards due to the negative user
        mintToken(deployer.borrowAsset(), address(this), REWARDS);
        IToken(deployer.borrowAsset()).approve(address(vaultRegistry), REWARDS);
        vaultRegistry.injectBorrowAssetsInVault(deployer.supplyAsset(), deployer.borrowAsset(), REWARDS);

        vault.updatePosition(user1);
        vault.updatePosition(user2);

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(1);
        assertEq(harvest.farmEarnings, REWARDS);

        assertGt(vault.getUserHarvest(user1).claimableEarnings, REWARDS);
        assertEq(vault.getUserHarvest(user2).claimableEarnings, 0);
        assertEq(vault.debtToken().balanceOf(user2), BORROW);
    }

    // Commit harvest with active assets for a user that has participated the entire harvest period
    function test_CommitHarvestAAFullTime() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        vault.updatePosition(user);

        assertEq(vault.getHarvest(1).farmEarnings, vault.getUserHarvest(user).claimableEarnings);
    }

    // Commit harvest with active assets for a user that has participated the harvest period partially
    function test_CommitHarvestAAPartTime() public {
        address user = vm.addr(1);

        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        // Simulate vm.roll the hard way to simulate user enters between 2 harvests
        stdstore.target(address(vault)).sig("getUserHarvest(address)").with_key(user).depth(1).checked_write(6);

        stdstore.target(address(vault)).sig("getHarvest(uint256)").with_key(1).depth(9).checked_write(11);

        vault.updatePosition(user);

        (, , uint256 reserveBalance) = vault.getHarvestData();
        HarvestTypes.HarvestData memory harvest = vault.getHarvest(1);
        HarvestTypes.UserHarvestData memory userHarvest = vault.getUserHarvest(user);

        // User has joined in the middle of the harvest at he should receive only half of his potential rewards
        assertEq(harvest.farmEarnings, REWARDS);
        assertEq(reserveBalance, REWARDS / 2);
        assertEq(harvest.farmEarnings, userHarvest.claimableEarnings + reserveBalance);
    }

    function test_CommitHarvestWithFarmLossDistribution() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        deposit(user2);
        vault.rebalance();

        uint256 farmBalance = dispatcher.balance();

        // Simulate 100% farm loss
        harvestWithFarmLoss(farmBalance, farmBalance);

        vault.updatePosition(user1);
        vault.updatePosition(user2);

        assertEq(vault.debtToken().balanceOf(user1), farmBalance / 2);
        assertEq(vault.debtToken().balanceOf(user2), farmBalance / 2);
    }

    function test_CommitHarvestWithUncommittedLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 rewards = vaultBalance / 2;
        harvestWithRewards(rewards);

        // 100% vault balance + 50% uncommitted loss
        harvestWithFarmLoss(vaultBalance + rewards, vaultBalance + (rewards / 2));

        vault.updatePosition(user);

        // Uncommitted is to repay part of the loss
        assertEq(vault.debtToken().balanceOf(user), vaultBalance - (rewards / 2));
    }

    function test_CommitHarvestWithRewardsLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        uint256 rewards = vaultBalance / 2;
        harvestWithRewards(rewards);

        // Turn uncommitted into claimable earnings
        vault.updatePosition(user);

        HarvestTypes.UserHarvestData memory userHarvest = vault.getUserHarvest(user);
        assertEq(userHarvest.claimableEarnings, rewards);

        // Accumulate more uncommitted
        harvestWithRewards(rewards);

        // 100% vault balance + 100% uncommitted + 50% claimable loss
        harvestWithFarmLoss(vaultBalance + rewards * 2, vaultBalance + rewards + rewards / 2);

        vault.updatePosition(user);

        userHarvest = vault.getUserHarvest(user);
        assertEq(userHarvest.claimableEarnings, rewards / 2);

        // Claimable is to repay part of the loss
        assertEq(vault.debtToken().balanceOf(user), vaultBalance);
    }

    function test_CommitHarvestUpdatesUserGlobalParams() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        deposit(user2);
        vault.rebalance();
        harvestWithRewards();

        vault.updatePosition(user1);

        (uint256 realClaimable, uint256 realUncommitted, ) = vault.getHarvestData();
        assertEq(realClaimable, REWARDS / 2);
        assertEq(realUncommitted, REWARDS / 2);

        vault.updatePosition(user2);

        (realClaimable, realUncommitted, ) = vault.getHarvestData();
        assertEq(realClaimable, REWARDS);
        assertEq(realUncommitted, 0);

        HarvestTypes.UserHarvestData memory userHarvest = vault.getUserHarvest(user1);

        assertEq(userHarvest.harvestId, 1);
        assertEq(userHarvest.claimableEarnings, REWARDS / 2);
        assertEq(userHarvest.harvestJoiningBlock, block.number);
        assertEq(userHarvest.uncommittedEarnings, 0);
        assertEq(userHarvest.vaultReserveUncommitted, 0);

        assertEq(vault.userSnapshots(user1), 1);
    }

    function test_CommitHarvestRepaysPartOfTheDebt() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 rewards = vault.debtToken().balanceOf(address(vault));
        harvestWithRewards(rewards);

        vault.updatePosition(user);

        assertEq(vault.debtToken().balanceOf(user), BORROW - rewards);
    }

    function test_CommitHarvestRepaysEntireDebt() public {
        // Full debt repayment turns the remaining rewards into claimable
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        uint256 rewards = BORROW * 2; // 1 BORROW for full repayment and 1 for claimable
        harvestWithRewards(rewards);

        vault.updatePosition(user);

        assertEq(vault.debtToken().balanceOf(user), 0);

        HarvestTypes.UserHarvestData memory userHarvest = vault.getUserHarvest(user);
        assertEq(userHarvest.claimableEarnings, rewards / 2);
    }

    function test_CommitSupplyLoss() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
        assertEq(vault.debtToken().balanceOf(user), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
    }

    function test_CommitSupplyLossWithShortage() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate shortage(farm loss) -> 50%
        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        burnToken(deployer.borrowAsset(), address(dispatcher), vaultBalance / 2);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(
            vault.debtToken().balanceOf(user),
            BORROW - supplyLossSnapshot.borrowLossAtSnapshot + supplyLossSnapshot.withdrawShortage
        );
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
    }

    function test_CommitSupplyLossWithSupplyFee() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        deposit(user2);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user1);
        vault.updatePosition(user2);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.supplyToken().balanceOf(user1), DEPOSIT - supplyLossSnapshot.fee / 2);
        assertEq(vault.supplyToken().balanceOf(user2), DEPOSIT - supplyLossSnapshot.fee / 2);
    }

    function test_CommitSupplyLossWithNoBorrowLoss() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% supply loss, 0 borrow loss
        simulateSupplyLoss(50, 0, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.debtToken().balanceOf(user), BORROW);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
    }

    function test_CommitSupplyLossRecovery() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // Simulate deposit rewards
        uint256 profit = DEPOSIT;
        BaseLenderStrategy(address(lenderStrategy)).setDepositRewards(profit);

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.debtToken().balanceOf(user), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT + supplyLossSnapshot.supplyLossProfit);
    }

    function test_CommitSupplyLossMoreThanSupplyBalance() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        depositAndBorrow(user2);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(90, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user1);
        vault.updatePosition(user2);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.debtToken().balanceOf(user1), 0);
        assertEq(vault.debtToken().balanceOf(user2), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
        assertEq(vault.supplyToken().balanceOf(user1), DEPOSIT);
        assertEq(vault.supplyToken().balanceOf(user2), 0);
    }

    function test_CommitPartially() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePositionTo(user, 1);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.debtToken().balanceStored(user), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
        assertEq(vault.supplyToken().balanceStored(user), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
    }

    function test_CommitPartiallyToLastCommit() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePositionTo(user, 2);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertEq(vault.debtToken().balanceStored(user), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
        assertEq(vault.supplyToken().balanceStored(user), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
    }

    function test_CommitPartiallyAndFullyProvidesTheSameResult() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // Store the state to revert back to
        uint256 stateId = vm.snapshotState();

        vault.updatePositionTo(user, 1);
        vault.updatePositionTo(user, 2);

        uint256 userSupplyBalance = vault.supplyToken().balanceOf(user);
        uint256 userDebtBalance = vault.debtToken().balanceOf(user);

        vm.revertToState(stateId);

        vault.updatePosition(user);

        assertEq(vault.supplyToken().balanceOf(user), userSupplyBalance);
        assertEq(vault.debtToken().balanceOf(user), userDebtBalance);
    }

    function test_CommitMultipleUsers() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        depositAndBorrow(user1);
        deposit(user2);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        vault.updatePositions(users);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);

        assertEq(vault.debtToken().balanceOf(user1), BORROW - supplyLossSnapshot.borrowLossAtSnapshot);
        assertEq(vault.supplyToken().balanceOf(user1), DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot);
        assertEq(vault.debtToken().balanceOf(user2), 0);
        assertEq(vault.supplyToken().balanceOf(user2), DEPOSIT);
    }

    function test_CommitAccumulateInterestUpToNow() public {
        // As there is time passing from the time of the snapshot up to now, there is interest being accumulated
        // The user's position should be up-to-date
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);
        vault.snapshotSupplyLoss();

        // Simulate interest
        accumulateInterest(100, 100);

        vault.updatePosition(user);

        SupplyLossTypes.SupplyLoss memory supplyLossSnapshot = vault.getSupplyLossSnapshot(0);
        assertApproxEqAbs(
            vault.supplyToken().balanceOf(user),
            DEPOSIT - supplyLossSnapshot.supplyLossAtSnapshot + 100, // interest being accumulated
            5 // wei rounding tolerance
        );
        assertApproxEqAbs(
            vault.debtToken().balanceOf(user),
            BORROW - supplyLossSnapshot.borrowLossAtSnapshot + 100, // interest being accumulated
            5 // wei rounding tolerance
        );

        CommonTypes.SnapshotType memory snapshotGeneric = vault.getSnapshot(0);
        assertGt(vault.debtToken().userIndex(user), snapshotGeneric.supplyIndex);
        assertGt(vault.supplyToken().userIndex(user), snapshotGeneric.borrowIndex);
    }

    function test_CommitVault() public {
        vm.expectRevert(IHarvestableManager.HM_V1_INVALID_COMMIT.selector);
        vault.updatePosition(address(vault));
    }

    function test_CommitVaultPartially() public {
        vm.expectRevert(IHarvestableManager.HM_V1_INVALID_COMMIT.selector);
        vault.updatePositionTo(address(vault), 5);
    }

    function test_InjectSupply() public {
        address user = vm.addr(1);
        deposit(user);

        uint256 supplyIndex = vault.supplyToken().interestIndex();
        uint256 injectionAmount = DEPOSIT;

        mintToken(deployer.supplyAsset(), address(this), injectionAmount);
        IToken(deployer.supplyAsset()).approve(address(vault), injectionAmount);
        vaultRegistry.injectSupplyInVault(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            injectionAmount,
            vault.supplyToken().calcNewIndex()
        );

        assertEq(vault.supplyToken().interestIndex(), supplyIndex); // Index has not been changed
        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT);
        assertEq(lenderStrategy.supplyBalance(), DEPOSIT * 2);
    }

    function test_InjectSupplyMoreThanIntended() public {
        address user = vm.addr(1);
        deposit(user);
        // user has 1 at index 1 and lender balance 1

        uint256 supplyIndex = vault.supplyToken().interestIndex();
        // Simulate deposit rewards
        uint256 depositRewards = DEPOSIT * 2;
        BaseLenderStrategy(address(lenderStrategy)).setDepositRewards(depositRewards);

        mintToken(deployer.supplyAsset(), address(this), DEPOSIT);
        IToken(deployer.supplyAsset()).approve(address(vault), DEPOSIT);
        // we inject 1, so we want the user to have 1 at index 1 and lender balance 2
        vaultRegistry.injectSupplyInVault(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            DEPOSIT,
            vault.supplyToken().calcNewIndex()
        );
        // to distribute the extra 2 rewards, the index goes from 1 to 2, because lender unexpectedly went from 2 to 4
        // hence the user should have 1 * 2 = 2

        assertEq(vault.supplyToken().balanceOf(user), DEPOSIT * 2);

        assertGt(vault.supplyToken().interestIndex(), supplyIndex);
    }

    function test_InjectSupplyLessThanIntended() public {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        deposit(user1);
        depositAndBorrow(user2);
        vault.rebalance();

        // 90% supply loss and 50% borrow loss
        simulateSupplyLoss(90, 50, 0);
        vault.snapshotSupplyLoss();

        vault.updatePosition(user1);
        vault.updatePosition(user2);

        uint256 supplyBalance = lenderStrategy.supplyBalance();
        uint256 injectionAmount = vault.supplyToken().balanceOf(user1) - lenderStrategy.supplyBalance();

        // Simulate deposit fee
        BaseLenderStrategy(address(lenderStrategy)).setDepositFee(90); // 90% * injectionAmount

        mintToken(deployer.supplyAsset(), address(this), injectionAmount);
        IToken(deployer.supplyAsset()).approve(address(vault), injectionAmount);
        vaultRegistry.injectSupplyInVault(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            injectionAmount,
            vault.supplyToken().calcNewIndex()
        );

        assertEq(vault.supplyToken().balanceOf(user1), DEPOSIT);
        uint256 injectionFee = (injectionAmount * 90) / 100;
        assertEq(supplyBalance + injectionAmount - injectionFee, lenderStrategy.supplyBalance());
    }

    function test_InjectSupplyWhenSnapshotNeeded() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        simulateSupplyLoss(50, 50, 0);

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IInterestVault.IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED.selector);
        vaultRegistry.injectSupplyInVault(supplyAsset, borrowAsset, 1, 1);
    }

    function test_InjectSupplyNonOwner() public {
        address user = vm.addr(1);

        vm.expectRevert(IVaultStorage.VS_V1_ONLY_OWNER.selector);
        vault.injectSupply(1, 1, user);
    }

    function test_CalcCommitUserWhenSnapshotNeeded() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();

        // 50% loss
        simulateSupplyLoss(50, 50, 0);

        vm.expectRevert(IInterestVault.IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED.selector);
        vault.calcCommitUser(user, 0);
    }
}
