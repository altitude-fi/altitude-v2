// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {TestDeployer} from "../TestDeployer.sol";
import {TokensGenerator} from "./TokensGenerator.sol";
import {BasePriceSource} from "../base/BasePriceSource.sol";

import {BaseLenderStrategy} from "../base/BaseLenderStrategy.sol";

import {IToken} from "../interfaces/IToken.sol";
import {IIngress} from "../../contracts/interfaces/internal/access/IIngress.sol";
import {IVaultCoreV1} from "../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {ILenderStrategy} from "../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IFarmDispatcher} from "../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";

import {VaultTypes} from "../../contracts/libraries/types/VaultTypes.sol";
import {VaultRegistryV1} from "../../contracts/vaults/v1/VaultRegistry.sol";

abstract contract VaultTestSuite is TokensGenerator {
    uint256 public constant DEPOSIT = 10e18;
    uint256 public constant WITHDRAW = 10e18;
    uint256 public constant BORROW = 5e6;
    uint256 public constant REPAY = 2e6;
    uint256 public constant REWARDS = 100e6;
    uint256 public constant RESERVE_BALANCE = 100e6;
    uint256 public constant FARM_LOSS = 101e6; // amount of farm loss

    TestDeployer public deployer;
    IVaultCoreV1 public vault;
    VaultRegistryV1 public vaultRegistry;

    function setUp() public virtual {
        deployer = new TestDeployer();
        deployer.initDeployer(address(deployer), address(this));

        vaultRegistry = deployer.deployDefaultProtocol();
        vault = deployer.deployDefaultVault(vaultRegistry);
    }

    function deposit(address user) public {
        _deposit(user, user, DEPOSIT);
    }

    function deposit(address user, uint256 amount) public {
        _deposit(user, user, amount);
    }

    function deposit(address user, address onBehalf) public {
        _deposit(user, onBehalf, DEPOSIT);
    }

    function deposit(address user, address onBehalf, uint256 amount) public {
        _deposit(user, onBehalf, amount);
    }

    function _deposit(address user, address onBehalf, uint256 amount) internal {
        vm.startPrank(user);
        mintToken(deployer.supplyAsset(), user, amount);
        IToken(deployer.supplyAsset()).approve(address(vault), amount);
        vault.deposit(amount, onBehalf);
        vm.stopPrank();
    }

    function depositAndBorrow(address user) public {
        _depositAndBorrow(user, DEPOSIT, BORROW);
    }

    function depositAndBorrow(address user, uint256 depositAmount) public {
        _depositAndBorrow(user, depositAmount, BORROW);
    }

    function depositAndBorrow(address user, uint256 depositAmount, uint256 borrowAmount) public {
        _depositAndBorrow(user, depositAmount, borrowAmount);
    }

    function _depositAndBorrow(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        mintToken(deployer.supplyAsset(), user, depositAmount);
        IToken(deployer.supplyAsset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vault.borrow(borrowAmount);
        vm.stopPrank();
    }

    function repay(address user) public {
        _repay(user, user, REPAY);
    }

    function repay(address user, address onBehalf) public {
        _repay(user, onBehalf, REPAY);
    }

    function repay(address user, uint256 amount) public {
        _repay(user, user, amount);
    }

    function repay(address user, address onBehalf, uint256 amount) public {
        _repay(user, onBehalf, amount);
    }

    function _repay(address user, address onBehalf, uint256 amount) internal {
        vm.startPrank(user);
        // Mint tokens to the user to be able to repay the amount
        mintToken(deployer.borrowAsset(), user, amount);
        IToken(deployer.borrowAsset()).approve(address(vault), amount);
        vault.repay(amount, onBehalf);
        vm.stopPrank();
    }

    function depositAndWithdraw(address user) public {
        _depositAndWithdraw(user, DEPOSIT, WITHDRAW);
    }

    function depositAndWithdraw(address user, uint256 depositAmount, uint256 withdrawAmount) public {
        _depositAndWithdraw(user, depositAmount, withdrawAmount);
    }

    function _depositAndWithdraw(address user, uint256 depositAmount, uint256 withdrawAmount) internal {
        vm.startPrank(user);
        mintToken(deployer.supplyAsset(), user, depositAmount);
        IToken(deployer.supplyAsset()).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vault.withdraw(withdrawAmount, user);
        vm.stopPrank();
    }

    function harvestWithRewards() public {
        _harvestWithRewards(REWARDS);
    }

    function harvestWithRewards(uint256 rewards) public {
        _harvestWithRewards(rewards);
    }

    function _harvestWithRewards(uint256 rewards) internal {
        // Execute a harvest (2 harvests can not be processed into 1 block)
        // When the vault gets deployed it runs an initial harvest
        vm.roll(block.number + 1);
        // Generate rewards
        mintToken(deployer.borrowAsset(), vault.activeFarmStrategy(), rewards);
        vaultRegistry.harvestVault(deployer.supplyAsset(), deployer.borrowAsset(), getPrice());
    }

    function harvestWithFarmLoss(uint256 farmBalance, uint256 farmLoss) public {
        vm.mockCall(
            vault.activeFarmStrategy(),
            abi.encodeWithSelector(IFarmDispatcher.balance.selector),
            abi.encode(farmBalance - farmLoss)
        );

        // Execute a harvest (2 harvests can not be processed into 1 block)
        vm.roll(block.number + 1);
        vaultRegistry.harvestVault(deployer.supplyAsset(), deployer.borrowAsset(), getPrice());
    }

    function withdrawReserve(uint256 withdrawAmount) public {
        mintToken(deployer.borrowAsset(), address(this), RESERVE_BALANCE);
        IToken(deployer.borrowAsset()).transfer(address(vault), RESERVE_BALANCE);

        vaultRegistry.withdrawVaultReserve(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            RESERVE_BALANCE + withdrawAmount
        );
    }

    function disableReserveFactor() public {
        (address snapshotableManager, ) = vault.getSnapshotableConfig();
        vaultRegistry.setSnapshotableConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.SnapshotableConfig(snapshotableManager, 0)
        );
    }

    function enableReserveFactor() public {
        (address snapshotableManager, ) = vault.getSnapshotableConfig();
        vaultRegistry.setSnapshotableConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.SnapshotableConfig(snapshotableManager, deployer.RESERVE_FACTOR())
        );
    }

    function simulateSupplyLoss(uint256 supplyPerc, uint256 borrowPerc, uint256 feePerc) public {
        BaseLenderStrategy(vault.activeLenderStrategy()).setSupplyLoss(supplyPerc, borrowPerc, feePerc);
    }

    function accumulateInterest(uint256 supplyInterest, uint256 borrowInterest) public {
        BaseLenderStrategy(vault.activeLenderStrategy()).accumulateInterest(supplyInterest, borrowInterest);
    }

    function setPrice(address from, address to, uint256 price) public {
        BasePriceSource oracle = BasePriceSource(deployer.priceProvider());
        oracle.setInBase(from, to, price);
        oracle.setInBase(to, from, (10 ** IToken(from).decimals() * 10 ** IToken(to).decimals()) / price);
    }

    function getPrice() public view returns (uint256) {
        return
            ILenderStrategy(vault.activeLenderStrategy()).getInBase(vault.supplyUnderlying(), vault.borrowUnderlying());
    }

    function setBorrowLimits(uint256 sLimit, uint256 lLimit, uint256 tLimit) public {
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(sLimit, lLimit, tLimit)
        );
    }

    function snapshotSupply_50_Loss(uint256 price) public {
        simulateSupplyLoss(50, 50, 0);
        setPrice(deployer.supplyAsset(), deployer.borrowAsset(), price);
        vault.snapshotSupplyLoss();
        IIngress(vault.ingressControl()).setProtocolPause(false);
    }
}
