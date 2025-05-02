pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {BaseGetter} from "../../base/BaseGetter.sol";
import {TestDeployer} from "../../TestDeployer.sol";
import {Roles} from "../../../contracts/common/Roles.sol";
import {VaultTypes} from "../../../contracts/libraries/types/VaultTypes.sol";
import {VaultRegistryV1} from "../../../contracts/vaults/v1/VaultRegistry.sol";
import {IToken} from "../../interfaces/IToken.sol";
import {IVaultCoreV1} from "../../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {ISwapStrategy} from "../../../contracts/interfaces/internal/strategy/swap/ISwapStrategy.sol";
import {IFarmDispatcher} from "../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {IVaultRegistryV1} from "../../../contracts/interfaces/internal/vault/IVaultRegistry.sol";
import {IHarvestableManager} from "../../../contracts/interfaces/internal/vault/extensions/harvestable/IHarvestableManager.sol";
import {ILiquidatableManager} from "../../../contracts/interfaces/internal/vault/extensions/liquidatable/ILiquidatableManager.sol";
import {IVaultCoreV1Initializer} from "../../../contracts/interfaces/internal/vault/IVaultCoreV1Initializer.sol";

contract VaultRegistryTest is Test {
    using stdStorage for StdStorage;

    TestDeployer public deployer;

    VaultRegistryV1 public vaultRegistry;

    function setUp() public {
        deployer = new TestDeployer();
        deployer.initDeployer(address(deployer), address(this));
        vaultRegistry = deployer.deployDefaultProtocol();

        // Grant role for the tests
        vaultRegistry.grantRole(Roles.ALPHA, address(this));
        vaultRegistry.grantRole(Roles.BETA, address(this));
        vaultRegistry.grantRole(Roles.GAMMA, address(this));
        vaultRegistry.grantRole(Roles.BETA, address(deployer));
    }

    function test_CorrectInitialization() public view {
        assertEq(vaultRegistry.vaultInitImpl(), deployer.vaultInitImpl());
        assertEq(vaultRegistry.proxyAdmin(), deployer.UPGRADABILITY_EXECUTOR());
        assertEq(vaultRegistry.hasRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), address(this)), true);
    }

    function test_InitializationWithZeroAddresses() public {
        vaultRegistry = new VaultRegistryV1();

        address admin = address(this);
        address proxyAdmin = deployer.UPGRADABILITY_EXECUTOR();

        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.initialize(
            VaultTypes.RegistryConfiguration(
                address(0),
                vm.addr(1), // tokensFactory
                vm.addr(2), // vaultInitImpl
                proxyAdmin
            )
        );

        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.initialize(
            VaultTypes.RegistryConfiguration(
                admin,
                address(0), // tokensFactory
                vm.addr(2), // vaultInitImpl
                proxyAdmin
            )
        );

        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.initialize(
            VaultTypes.RegistryConfiguration(
                admin,
                vm.addr(1), // tokensFactory
                address(0), // vaultInitImpl
                proxyAdmin
            )
        );

        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.initialize(
            VaultTypes.RegistryConfiguration(
                admin,
                vm.addr(1), // tokensFactory
                vm.addr(2), // vaultInitImpl
                address(0)
            )
        );
    }

    function test_ReInitialization() public {
        address admin = address(this);
        address proxyAdmin = deployer.UPGRADABILITY_EXECUTOR();
        vm.expectRevert("Initializable: contract is already initialized");
        vaultRegistry.initialize(
            VaultTypes.RegistryConfiguration(
                admin,
                vm.addr(1), // tokensFactory
                vm.addr(2), // vaultInitImpl
                proxyAdmin
            )
        );
    }

    function test_DeployVault() public {
        deployer.deployDefaultVault(vaultRegistry);

        assertTrue(vaultRegistry.vaultsArray(0) != address(0));
        assertTrue(vaultRegistry.vaults(deployer.supplyAsset(), deployer.borrowAsset()) != address(0));
        assertEq(vaultRegistry.vaultsCount(), 1);
    }

    function test_ReDeployVault() public {
        deployer.deployDefaultVault(vaultRegistry);

        vm.expectRevert(IVaultRegistryV1.VR_V1_ALREADY_EXISTING_VAULT.selector);
        deployer.deployDefaultVault(vaultRegistry);
    }

    function test_UpdateVaultConfig() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(address(0), 1e18, 1e18, address(0), address(0), address(0))
        );

        // We are testing if the setVaultConfig has been executed correctly.
        // For that reason a single check is enough
        assertEq(vault.ingressControl(), address(0));
    }

    function test_UpdateConfigNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.setVaultConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.VaultConfig(address(0), 1e18, 1e18, address(0), address(0), address(0))
        );
    }

    function test_NoRoleUpdateVaultConfig() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setVaultConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.VaultConfig(address(0), 1e18, 1e18, address(0), address(0), address(0))
        );
    }

    function test_UpdateSnapshotableConfig() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        vaultRegistry.setSnapshotableConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.SnapshotableConfig(address(0), 1e18)
        );

        (address snapshotableManager, ) = vault.getSnapshotableConfig();
        assertEq(snapshotableManager, address(0));
    }

    function test_UpdateSnapshotableConfigNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.setSnapshotableConfig(supplyAsset, borrowAsset, VaultTypes.SnapshotableConfig(address(0), 1e18));
    }

    function test_NoRoleUpdateSnapshotableConfig() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setSnapshotableConfig(supplyAsset, borrowAsset, VaultTypes.SnapshotableConfig(address(0), 1e18));
    }

    function test_SnapshotableConfigReserveFactorOutOfRange() public {
        deployer.deployDefaultVault(vaultRegistry);
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultCoreV1Initializer.HV_V1_RESERVE_FACTOR_OUT_OF_RANGE.selector);
        vaultRegistry.setSnapshotableConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.SnapshotableConfig(address(0), 1e18 + 1)
        );
    }

    function test_UpdateGroomableConfig() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        vaultRegistry.setGroomableConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.GroomableConfig(address(0), address(0), 1e18)
        );

        (address groomableManager, , ) = vault.getGroomableConfig();
        assertEq(groomableManager, address(0));
    }

    function test_UpdateGroomableConfigNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.setGroomableConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.GroomableConfig(address(0), address(0), 1e18)
        );
    }

    function test_NoRoleUpdateGroomableConfig() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setGroomableConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.GroomableConfig(address(0), address(0), 1e18)
        );
    }

    function test_UpdateGroomableConfigOutOfRange() public {
        deployer.deployDefaultVault(vaultRegistry);
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultCoreV1Initializer.GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE.selector);
        vaultRegistry.setGroomableConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.GroomableConfig(address(0), address(0), 1e18 + 1)
        );
    }

    function test_UpdateLiquidationConfig() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        vaultRegistry.setLiquidationConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.LiquidatableConfig(address(0), 1e18, 1e18)
        );

        (address liquidatableManager, , ) = vault.getLiquidationConfig();
        assertEq(liquidatableManager, address(0));
    }

    function test_UpdateLiquidationConfigNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.setLiquidationConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.LiquidatableConfig(address(0), 1e18, 1e18)
        );
    }

    function test_NoRoleUpdateLiquidationConfig() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setLiquidationConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.LiquidatableConfig(address(0), 1e18, 1e18)
        );
    }

    function test_UpdateLiquidationBonusOutOfRange() public {
        deployer.deployDefaultVault(vaultRegistry);
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(ILiquidatableManager.LQ_V1_MAX_BONUS_OUT_OF_RANGE.selector);
        vaultRegistry.setLiquidationConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.LiquidatableConfig(address(0), 1e18, 1e18 + 1)
        );
    }

    function test_UpdateLiquidationLiquidationPositionOutOfRange() public {
        deployer.deployDefaultVault(vaultRegistry);
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(ILiquidatableManager.LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE.selector);
        vaultRegistry.setLiquidationConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.LiquidatableConfig(address(0), 1e18 + 1, 1e18)
        );
    }

    function test_UpdateBorrowLimits() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(0, 0, 0)
        );

        assertEq(vault.supplyThreshold(), 0);
        assertEq(vault.targetThreshold(), 0);
        assertEq(vault.liquidationThreshold(), 0);
    }

    function test_UpdateBorrowLimitsNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(0, 0, 0));
    }

    function test_NoRoleUpdateBorrowLimits() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(0, 0, 0));
    }

    function test_ReduceTargetThreshold() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        vaultRegistry.reduceVaultTargetThreshold(deployer.supplyAsset(), deployer.borrowAsset(), 0);

        assertEq(vault.targetThreshold(), 0);
    }

    function test_test_ReduceTargetThresholdNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.reduceVaultTargetThreshold(supplyAsset, borrowAsset, 0);
    }

    function test_NoRoleReduceTargetThreshold() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.reduceVaultTargetThreshold(supplyAsset, borrowAsset, 0);
    }

    function test_UpdateProxyAdmin() public {
        vaultRegistry.setProxyAdmin(address(0x1));
        assertEq(vaultRegistry.proxyAdmin(), address(0x1));
    }

    function test_NoRoleUpdateProxyAdmin() public {
        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setProxyAdmin(address(0x1));
    }

    function test_UpdateProxyAdminWithAddressZero() public {
        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.setProxyAdmin(address(0));
    }

    function test_UpdateVaultInitImpl() public {
        vaultRegistry.setInitImpl(address(0x1));
        assertEq(vaultRegistry.vaultInitImpl(), address(0x1));
    }

    function test_NoRoleUpdateVaultInitImpl() public {
        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setInitImpl(address(0x1));
    }

    function test_UpdateVaultInitImplWithZeroAddress() public {
        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.setInitImpl(address(0));
    }

    function test_UpdateTokensFactory() public {
        vaultRegistry.setTokensFactory(address(0x1));
        assertEq(vaultRegistry.tokensFactory(), address(0x1));
    }

    function test_NoRoleUpdateTokensFactory() public {
        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setTokensFactory(address(0x1));
    }

    function test_UpdateTokensFactoryWithZeroAddress() public {
        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.setTokensFactory(address(0));
    }

    function test_WithdrawReserveNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.withdrawVaultReserve(supplyAsset, borrowAsset, 0);
    }

    function test_NoRoleWithdrawReserve() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.withdrawVaultReserve(supplyAsset, borrowAsset, 0);
    }

    function test_WithdrawReserveNoReceiver() public {
        deployer.deployDefaultVault(vaultRegistry);
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        // Simulate no receiver
        stdstore.target(address(vaultRegistry)).sig("vaultReserveReceiver()").checked_write(address(0));

        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.withdrawVaultReserve(supplyAsset, borrowAsset, 0);
    }

    function test_UpdateReserveReceiver() public {
        vaultRegistry.setVaultReserveReceiver(address(0x1));
        assertEq(vaultRegistry.vaultReserveReceiver(), address(0x1));
    }

    function test_UpdateReserveReceiverToZeroAddress() public {
        vm.expectRevert(IVaultRegistryV1.VR_V1_ZERO_ADDRESS.selector);
        vaultRegistry.setVaultReserveReceiver(address(0));
    }

    function test_NoRoleUpdateReserveReceiver() public {
        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.setVaultReserveReceiver(address(0x1));
    }

    function test_InjectSupply() public {
        deployer.deployDefaultVault(vaultRegistry);
        vaultRegistry.injectSupplyInVault(deployer.supplyAsset(), deployer.borrowAsset(), 0, 1);
    }

    function test_InjectSupplyNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.injectSupplyInVault(supplyAsset, borrowAsset, 0, 1);
    }

    function test_NoRoleInjectSupply() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.injectSupplyInVault(supplyAsset, borrowAsset, 0, 1);
    }

    function test_MigrateLender() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        address newLendingStrategy = BaseGetter.getBaseLenderStrategy(
            address(vault),
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            vault.activeFarmStrategy(),
            deployer.priceProvider()
        );

        vaultRegistry.changeVaultLendingProvider(deployer.supplyAsset(), deployer.borrowAsset(), newLendingStrategy);

        assertEq(vault.activeLenderStrategy(), newLendingStrategy);
    }

    function test_MigrateLenderNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, address(0));
    }

    function test_NoRoleMigrateLender() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.changeVaultLendingProvider(supplyAsset, borrowAsset, address(0));
    }

    function test_ChangeVaultFarmDispatcher() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);
        address newFarmDispatcher = makeAddr("newFarmDispatcher");
        vm.mockCall(newFarmDispatcher, abi.encodeWithSelector(IFarmDispatcher.dispatch.selector), abi.encode());

        vaultRegistry.changeVaultFarmDispatcher(deployer.supplyAsset(), deployer.borrowAsset(), newFarmDispatcher);
        assertEq(vault.activeFarmStrategy(), newFarmDispatcher);
    }

    function test_ChangeVaultFarmDispatcherNotExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.changeVaultFarmDispatcher(supplyAsset, borrowAsset, address(0));
    }

    function test_NoRolechangeVaultFarmDispatcher() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.changeVaultFarmDispatcher(supplyAsset, borrowAsset, address(0));
    }

    function test_Harvest() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        // Mock harvest execution as that is not responsibility of the registy
        vm.mockCall(address(vault), abi.encodeWithSelector(IHarvestableManager.harvest.selector, 0), abi.encode());

        vaultRegistry.harvestVault(deployer.supplyAsset(), deployer.borrowAsset(), 0);
    }

    function test_HarvestNoExistingVault() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.harvestVault(supplyAsset, borrowAsset, 0);
    }

    function test_NoRoleHarvest() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.harvestVault(supplyAsset, borrowAsset, 0);
    }

    function test_DisableOnBehalfValidation() public {
        IVaultCoreV1 vault = deployer.deployDefaultVault(vaultRegistry);

        bytes4[] memory functions = new bytes4[](1);
        functions[0] = 0x12345678;

        vaultRegistry.disableVaultOnBehalfValidation(deployer.supplyAsset(), deployer.borrowAsset(), functions, true);

        assertEq(vault.onBehalfFunctions(0x12345678), true);
    }

    function test_DisableOnBehalfValidationNotExistingVault() public {
        bytes4[] memory functions = new bytes4[](1);
        functions[0] = 0x12345678;

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.expectRevert(IVaultRegistryV1.VR_V1_NONEXISTING_VAUlT.selector);
        vaultRegistry.disableVaultOnBehalfValidation(supplyAsset, borrowAsset, functions, true);
    }

    function test_NoRoleDisableOnBehalfValidation() public {
        bytes4[] memory functions = new bytes4[](1);
        functions[0] = 0x12345678;

        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        vm.prank(vm.addr(2));
        vm.expectRevert();
        vaultRegistry.disableVaultOnBehalfValidation(supplyAsset, borrowAsset, functions, true);
    }
}
