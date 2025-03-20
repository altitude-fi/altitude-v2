pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";
import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";
import {HarvestTypes} from "../../../contracts/libraries/types/HarvestTypes.sol";
import {IVaultStorage} from "../../../contracts/interfaces/internal/vault/IVaultStorage.sol";

import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IHarvestableManager} from "../../../contracts/interfaces/internal/vault/extensions/harvestable/IHarvestableManager.sol";

contract VaultHarvestableTest is VaultTestSuite {
    IFarmDispatcher dispatcher;
    ILenderStrategy lenderStrategy;

    function setUp() public override {
        super.setUp();

        dispatcher = IFarmDispatcher(vault.activeFarmStrategy());
        lenderStrategy = ILenderStrategy(vault.activeLenderStrategy());
    }

    function test_HarvestWithRewards() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(1);
        assertEq(harvest.blockNumber, block.number);
        assertEq(harvest.harvestId, 1); // On deployment the 1 harvest is made
        assertEq(harvest.activeAssetsThreshold, deployer.LIQUIDATION_THRESHOLD());
        assertEq(harvest.divertEarningsThreshold, deployer.TARGET_THRESHOLD());
        assertEq(harvest.price, getPrice());
        assertEq(harvest.vaultLoss, 0);
        assertEq(harvest.claimableLossPerc, 0);
        assertEq(harvest.uncommittedLossPerc, 0);
        // Convert deposit into debt amount and get it up to the target threshold
        assertEq(
            harvest.vaultActiveAssets,
            (lenderStrategy.convertToBase(DEPOSIT, deployer.supplyAsset(), deployer.borrowAsset()) *
                deployer.LIQUIDATION_THRESHOLD()) / 1e18
        );
        assertEq(harvest.farmEarnings, REWARDS - reserveExpected);

        (uint256 claimable, uint256 uncommitted, uint256 reserve) = vault.getHarvestData();
        assertEq(claimable, 0);
        assertEq(uncommitted, REWARDS - reserveExpected);
        assertEq(reserve, reserveExpected);

        CommonTypes.SnapshotType memory snapshot = vault.getSnapshot(0);
        assertEq(snapshot.id, 1);
        assertEq(snapshot.kind, 0); // harvest type
        assertEq(snapshot.supplyIndex, vault.supplyToken().MATH_UNITS()); // There is no interest so the index should stay the same
        assertEq(snapshot.borrowIndex, vault.debtToken().MATH_UNITS()); // There is no interest so the index should stay the same

        // Ensure the vault has been committed
        assertEq(vault.userSnapshots(address(vault)), 1);
    }

    function test_HarvestWithVault_FarmLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        // 50% vault balance loss
        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        harvestWithFarmLoss(vaultBalance + REWARDS, vaultBalance / 2);

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(2);
        assertEq(harvest.vaultLoss, vaultBalance / 2);
        assertEq(harvest.claimableLossPerc, 0);
        assertEq(harvest.uncommittedLossPerc, 0);
        assertEq(harvest.farmEarnings, 0);
    }

    function test_HarvestWithVault_Uncommitted_FarmLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;

        // 100% vault balance + 50% rewards loss
        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        harvestWithFarmLoss(vaultBalance + REWARDS, vaultBalance + (REWARDS - reserveExpected) / 2);

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(2);
        assertEq(harvest.vaultLoss, vaultBalance);
        assertEq(harvest.claimableLossPerc, 0);
        assertEq(harvest.uncommittedLossPerc, 5e17); // 50%
        assertEq(harvest.farmEarnings, 0);

        (, uint256 uncommitted, ) = vault.getHarvestData();
        assertEq(uncommitted, (REWARDS - reserveExpected) / 2);
    }

    function test_HarvestWithVault_Uncommitted_Claimable_FarmLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        // Disable reserve factor for not charging user on commit
        disableReserveFactor();

        // Turn uncommitted into claimable earnings
        vault.updatePosition(user);

        // Reserve expected before resetting the reserve factor
        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        uint256 userRewardsExpected = REWARDS - reserveExpected;

        // 100% vault balance + 100% uncommitted + 50% claimable loss
        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        harvestWithFarmLoss(vaultBalance + REWARDS, vaultBalance + userRewardsExpected / 2);

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(2);
        assertEq(harvest.vaultLoss, vaultBalance);
        assertEq(harvest.claimableLossPerc, 5e17); // 50%
        assertEq(harvest.uncommittedLossPerc, 1e18); // 100%
        assertEq(harvest.farmEarnings, 0);

        (uint256 claimableRewards, uint256 uncommittedRewards, ) = vault.getHarvestData();
        assertEq(claimableRewards, userRewardsExpected / 2);
        assertEq(uncommittedRewards, 0);
    }

    function test_HarvestWithVault_Uncommitted_Claimable_Reserve_FarmLoss() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();
        harvestWithRewards();

        // Disable reserve factor for not charging user on commit
        disableReserveFactor();

        // Turn uncommitted into claimable earnings
        vault.updatePosition(user);

        // Reserve expected before resetting the reserve factor
        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        uint256 userRewardsExpected = REWARDS - reserveExpected;

        // 100% vault balance + 100% uncommitted + 100% claimable loss + 50% reserve
        uint256 vaultBalance = vault.debtToken().balanceOf(address(vault));
        harvestWithFarmLoss(vaultBalance + REWARDS, vaultBalance + userRewardsExpected + reserveExpected / 2);

        HarvestTypes.HarvestData memory harvest = vault.getHarvest(2);
        assertEq(harvest.vaultLoss, vaultBalance);
        assertEq(harvest.claimableLossPerc, 1e18); // 50%
        assertEq(harvest.uncommittedLossPerc, 1e18); // 100%
        assertEq(harvest.farmEarnings, 0);

        (uint256 claimableRewards, uint256 uncommittedRewards, uint256 vaultReserve) = vault.getHarvestData();
        assertEq(claimableRewards, 0);
        assertEq(uncommittedRewards, 0);
        assertEq(vaultReserve, reserveExpected / 2);
    }

    function test_VaultActiveAssetsWithNoBorrow() public {
        address user = vm.addr(1);
        deposit(user);
        harvestWithRewards();

        // Convert deposit into debt amount and get it up to the target threshold
        assertEq(
            vault.getHarvest(1).vaultActiveAssets,
            (lenderStrategy.convertToBase(DEPOSIT, deployer.supplyAsset(), deployer.borrowAsset()) *
                deployer.LIQUIDATION_THRESHOLD()) / 1e18
        );
    }

    function test_VaultActiveAssetsWithBorrow() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        harvestWithRewards();

        // Convert deposit into debt amount and get it up to the target threshold - user borrow
        assertEq(
            vault.getHarvest(1).vaultActiveAssets,
            (lenderStrategy.convertToBase(DEPOSIT, deployer.supplyAsset(), deployer.borrowAsset()) *
                deployer.LIQUIDATION_THRESHOLD()) /
                1e18 -
                BORROW
        );
    }

    function test_VaultActiveAssetsVaultDebtMoreThanTheLenderDebt() public {
        address user = vm.addr(1);
        deposit(user);
        vault.rebalance();

        // Simulate vault debt to be bigger than the lender debt
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IToken.totalSupply.selector),
            abi.encode(vault.debtToken().balanceOf(address(vault)) - 10) // 10 wei smaller
        );
        harvestWithRewards();

        // Convert deposit into debt amount and get it up to the target threshold - user borrow
        assertEq(
            vault.getHarvest(1).vaultActiveAssets,
            (lenderStrategy.convertToBase(DEPOSIT, deployer.supplyAsset(), deployer.borrowAsset()) *
                deployer.LIQUIDATION_THRESHOLD()) / 1e18
        );
    }

    function test_VaultActiveAssetsZero() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        uint256 price = getPrice();
        vm.roll(block.number + 1);
        vm.expectRevert(IHarvestableManager.HV_V1_HM_NO_ACTIVE_ASSETS.selector);
        vaultRegistry.harvestVault(supplyAsset, borrowAsset, price);
    }

    function test_HarvestWithNoRewardsNoReserveFee() public {
        address user = vm.addr(1);
        deposit(user);

        vm.roll(block.number + 1);
        vaultRegistry.harvestVault(deployer.supplyAsset(), deployer.borrowAsset(), getPrice());

        (, , uint256 vaultReserve) = vault.getHarvestData();
        assertEq(vaultReserve, 0);
    }

    function test_NonOwnerHarvest() public {
        uint256 price = getPrice();
        vm.roll(block.number + 1);
        vm.expectRevert(IVaultStorage.VS_V1_ONLY_OWNER.selector);
        vault.harvest(price);
    }

    function test_HarvestWithDifferentPrice() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        uint256 price = getPrice();
        vm.roll(block.number + 1);
        vm.expectRevert(IHarvestableManager.HM_V1_PRICE_TOO_LOW.selector);
        vaultRegistry.harvestVault(supplyAsset, borrowAsset, price * 2);
    }

    function test_2HarvestsInOneBlock() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        uint256 price = getPrice();
        vm.expectRevert(IHarvestableManager.HM_V1_BLOCK_ERROR.selector);
        vaultRegistry.harvestVault(supplyAsset, borrowAsset, price);
    }

    function test_InjectBorrowAsset() public {
        uint256 rewardsInjected = 10e6;
        mintToken(deployer.borrowAsset(), address(this), rewardsInjected);
        IToken(deployer.borrowAsset()).approve(address(vaultRegistry), rewardsInjected);
        vaultRegistry.injectBorrowAssetsInVault(deployer.supplyAsset(), deployer.borrowAsset(), rewardsInjected);

        (, uint256 uncommittedEarnings, ) = vault.getHarvestData();
        assertEq(uncommittedEarnings, rewardsInjected);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(address(dispatcher)), rewardsInjected);
    }

    function test_InjectZeroBorrowAssets() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IHarvestableManager.HM_V1_INVALID_INJECT_AMOUNT.selector);
        vaultRegistry.injectBorrowAssetsInVault(supplyAsset, borrowAsset, 0);
    }

    function test_WithdrawReserveFromBalance() public {
        withdrawReserve(0);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(vaultRegistry.vaultReserveReceiver()), RESERVE_BALANCE);
    }

    function test_WithdrawReserveFromFarm() public {
        address user = vm.addr(1);
        deposit(user);
        harvestWithRewards();

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        withdrawReserve(reserveExpected);

        assertEq(
            IToken(deployer.borrowAsset()).balanceOf(vaultRegistry.vaultReserveReceiver()),
            RESERVE_BALANCE + reserveExpected
        );

        (, , uint256 reserve) = vault.getHarvestData();
        assertEq(reserve, 0);
    }

    function test_WithdrawReserveAmountBiggerThanAvailable() public {
        withdrawReserve(RESERVE_BALANCE * 2);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(vaultRegistry.vaultReserveReceiver()), RESERVE_BALANCE);
    }

    function test_WithdrawReserveAvailableInFarm() public {
        address user = vm.addr(1);
        deposit(user);
        harvestWithRewards();

        // Simulate farm not available
        vm.mockCall(address(dispatcher), abi.encodeWithSelector(IFarmDispatcher.withdraw.selector), abi.encode(0));

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        withdrawReserve(RESERVE_BALANCE + reserveExpected);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(vaultRegistry.vaultReserveReceiver()), RESERVE_BALANCE);

        (, , uint256 reserve) = vault.getHarvestData();
        assertEq(reserve, reserveExpected);
    }

    function test_NonOwnerWithdrawReserve() public {
        vm.expectRevert(IVaultStorage.VS_V1_ONLY_OWNER.selector);
        vault.withdrawReserve(address(this), 1e6);
    }

    function test_ClaimRewardsWithNoDebt() public {
        address user = vm.addr(1);
        _prepareForClaim(user, REWARDS);

        uint256 claimableRewards = vault.claimableRewards(user);
        assertEq(claimableRewards, REWARDS);

        vm.prank(user);
        vault.claimRewards(claimableRewards); // claim all

        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), claimableRewards);

        (uint256 claimable, , ) = vault.getHarvestData();
        assertEq(claimable, 0);
        assertEq(vault.getUserHarvest(user).claimableEarnings, 0);
    }

    function test_ClaimRewardsNoMoreThanExisting() public {
        address user = vm.addr(1);
        _prepareForClaim(user, REWARDS);

        // Add even more balance
        mintToken(deployer.borrowAsset(), address(dispatcher), REWARDS);

        vm.prank(user);
        vault.claimRewards(type(uint256).max);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), REWARDS);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(address(dispatcher)), REWARDS);

        (uint256 claimable, , ) = vault.getHarvestData();
        assertEq(claimable, 0);
        assertEq(vault.getUserHarvest(user).claimableEarnings, 0);
    }

    function test_ClaimRewardsWithDebtPartiallyCovered() public {
        address user = vm.addr(1);
        uint256 rewards = BORROW / 2;
        _prepareForClaim(user, rewards);

        // Simulate for the user to have claimable and borrow in the same time
        vm.prank(user);
        vault.borrow(BORROW);

        assertEq(vault.claimableRewards(user), 0);

        vm.prank(user);
        vault.claimRewards(type(uint256).max);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW); // no rewards have been claimed

        (uint256 claimable, , ) = vault.getHarvestData();
        assertEq(claimable, 0);
        assertEq(vault.getUserHarvest(user).claimableEarnings, 0);
        assertEq(vault.debtToken().balanceOf(user), rewards);
    }

    function test_ClaimRewardsWithDebtFullyCovered() public {
        address user = vm.addr(1);
        _prepareForClaim(user, BORROW);

        // Simulate for the user to have claimable and borrow in the same time
        vm.prank(user);
        vault.borrow(BORROW);

        vm.prank(user);
        vault.claimRewards(type(uint256).max);

        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), BORROW); // no rewards have been claimed

        (uint256 claimable, , ) = vault.getHarvestData();
        assertEq(claimable, 0);
        assertEq(vault.getUserHarvest(user).claimableEarnings, 0);
        assertEq(vault.debtToken().balanceOf(user), 0);
    }

    function test_ClaimZeroRewards() public {
        vm.expectRevert(IHarvestableManager.HM_V1_CLAIM_REWARDS_ZERO.selector);
        vault.claimRewards(1);

        address user = vm.addr(1);
        deposit(user);
        harvestWithRewards(vault.claimableRewards(user));

        vm.expectRevert(IHarvestableManager.HM_V1_CLAIM_REWARDS_ZERO.selector);
        vault.claimRewards(0);
    }

    function test_ClaimRewardsAmountNotIntoTheFarm() public {
        address user = vm.addr(1);
        _prepareForClaim(user, REWARDS);

        uint256 claimableRewards = vault.claimableRewards(user);

        // Simulate farm not available
        vm.mockCall(address(dispatcher), abi.encodeWithSelector(IFarmDispatcher.withdraw.selector), abi.encode(0));

        vm.prank(user);
        vault.claimRewards(type(uint256).max); // claim all

        assertEq(IToken(deployer.borrowAsset()).balanceOf(user), 0);

        (uint256 claimable, , ) = vault.getHarvestData();
        assertEq(claimable, claimableRewards);
        assertEq(vault.getUserHarvest(user).claimableEarnings, claimableRewards);
    }

    function _prepareForClaim(address user, uint256 rewards) internal {
        // Disable reserve factor
        disableReserveFactor();

        deposit(user);
        harvestWithRewards(rewards);

        // Turn uncommitted into claimable earnings
        vault.updatePosition(user);
    }

    function test_ReserveAmount() public {
        address user = vm.addr(1);
        deposit(user);
        harvestWithRewards();

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        assertEq(reserveExpected, vault.reserveAmount());
    }

    function test_GetHarvestCount() public view {
        // Initial harvest
        assertEq(1, vault.getHarvestsCount());
    }

    function test_ClaimableEarningsMoreThanDebt() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();
        harvestWithRewards();

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        assertEq(vault.claimableRewards(user), REWARDS - reserveExpected - BORROW);
    }

    function test_ClaimableRewardsMoreThanDebt() public {
        address user = vm.addr(1);
        depositAndBorrow(user);
        vault.rebalance();
        harvestWithRewards();
        vault.updatePosition(user);

        uint256 farmLoss = 10e6;
        uint256 balance = dispatcher.balance();
        harvestWithFarmLoss(balance, farmLoss);

        uint256 reserveExpected = (REWARDS * deployer.RESERVE_FACTOR()) / 1e18;
        assertEq(
            vault.claimableRewards(user),
            REWARDS - farmLoss - reserveExpected - BORROW + 1 // rounding up
        );
    }
}
