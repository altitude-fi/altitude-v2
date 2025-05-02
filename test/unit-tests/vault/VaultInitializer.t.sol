pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestDeployer} from "../../TestDeployer.sol";
import {IConfig} from "../../../scripts/deployer/IConfig.sol";
import {IVaultCoreV1} from "../../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {VaultRegistryV1} from "../../../contracts/vaults/v1/VaultRegistry.sol";
import {IVaultCoreV1Initializer} from "../../../contracts/interfaces/internal/vault/IVaultCoreV1Initializer.sol";

contract VaultInitializerTest is Test {
    TestDeployer public deployer;
    VaultRegistryV1 public vaultRegistry;

    function setUp() public {
        deployer = new TestDeployer();
        deployer.initDeployer(address(deployer), address(this));

        vaultRegistry = deployer.deployDefaultProtocol();
    }

    function test_CorrectConfigurableVault() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        assertTrue(vault.owner() == address(vaultRegistry));
        assertTrue(vault.swapStrategy() != address(0));
        assertTrue(vault.ingressControl() != address(0));
        assertTrue(address(vault.borrowVerifier()) == deployer.borrowVerifier());
        assertTrue(vault.withdrawFeeFactor() == deployer.WITHDRAW_FEE_FACTOR());
        assertTrue(vault.withdrawFeePeriod() == deployer.WITHDRAW_FEE_PERIOD());
        assertTrue(vault.configurableManager() == deployer.configurableManager());
        assertTrue(vault.targetThreshold() == deployer.TARGET_THRESHOLD());
        assertTrue(vault.supplyThreshold() == deployer.SUPPLY_THRESHOLD());
        assertTrue(vault.liquidationThreshold() == deployer.LIQUIDATION_THRESHOLD());
        assertTrue(vault.activeFarmStrategy() != address(0));
        assertTrue(vault.activeLenderStrategy() != address(0));
    }

    function test_WithdrawFeeFactorHigherThanLimit() public {
        vm.mockCall(
            address(deployer),
            abi.encodeWithSelector(IConfig.WITHDRAW_FEE_FACTOR.selector),
            abi.encode(100e18)
        );
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_SupplyThresholdOutOfLimit() public {
        // Supply threshold bigger than 1e18
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.SUPPLY_THRESHOLD.selector), abi.encode(100e18));
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);

        // Supply threshold bigger than liquidation threhsold
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.SUPPLY_THRESHOLD.selector), abi.encode(9e17));
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_TargetThresholdOutOfLimit() public {
        // Target threshold bigger than 1e18
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.TARGET_THRESHOLD.selector), abi.encode(100e18));
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);

        // Target threshold bigger than liquidation threhsold
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.TARGET_THRESHOLD.selector), abi.encode(9e17));
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_LiquidationThresholdOutOfLimit() public {
        // Liquidation threshold bigger than 1e18
        vm.mockCall(
            address(deployer),
            abi.encodeWithSelector(IConfig.LIQUIDATION_THRESHOLD.selector),
            abi.encode(100e18)
        );
        vm.expectRevert(IVaultCoreV1Initializer.VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_CorrectGroomableVault() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        (address groomableManager, address flashLoanStrategy, uint256 maxMigrationFeePercentage) = vault
            .getGroomableConfig();

        assertTrue(groomableManager == deployer.groomableManager());
        assertTrue(flashLoanStrategy != address(0));
        assertTrue(maxMigrationFeePercentage == deployer.MAX_MIGRATION_FEE_PERCENTAGE());
    }

    function test_FeePercentageHigherThanLimit() public {
        vm.mockCall(
            address(deployer),
            abi.encodeWithSelector(IConfig.MAX_MIGRATION_FEE_PERCENTAGE.selector),
            abi.encode(100e18)
        );
        vm.expectRevert(IVaultCoreV1Initializer.GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_CorrectLiquidatableVault() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        (address liquidatableManager, uint256 maxPositionLiquidation, uint256 liquidationBonus) = vault
            .getLiquidationConfig();

        assertTrue(liquidatableManager == deployer.liquidatableManager());
        assertTrue(maxPositionLiquidation == deployer.MAX_POSITION_LIQUIDATION());
        assertTrue(liquidationBonus == deployer.LIQUIDATION_BONUS());
    }

    function test_LiquidationBonusHigherThanLimit() public {
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.LIQUIDATION_BONUS.selector), abi.encode(100e18));
        vm.expectRevert(IVaultCoreV1Initializer.LQ_V1_MAX_BONUS_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_PositionLiquidationHigherThanLimit() public {
        vm.mockCall(
            address(deployer),
            abi.encodeWithSelector(IConfig.MAX_POSITION_LIQUIDATION.selector),
            abi.encode(100e18)
        );
        vm.expectRevert(IVaultCoreV1Initializer.LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_CorrectSnapshotableVault() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        (address snapshotManager, uint256 reserveFactor) = vault.getSnapshotableConfig();

        assertTrue(snapshotManager == deployer.snapshotableManager());
        assertTrue(reserveFactor == deployer.RESERVE_FACTOR());
    }

    function test_ReserveFactorHigherThanLimit() public {
        vm.mockCall(address(deployer), abi.encodeWithSelector(IConfig.RESERVE_FACTOR.selector), abi.encode(100e18));
        vm.expectRevert(IVaultCoreV1Initializer.HV_V1_RESERVE_FACTOR_OUT_OF_RANGE.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_CorrectTokensSet() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        assertTrue(address(vault.debtToken()) != address(0));
        assertTrue(address(vault.supplyToken()) != address(0));
    }
}
