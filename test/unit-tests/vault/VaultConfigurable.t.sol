// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";
import {VaultTypes} from "../../../contracts/libraries/types/VaultTypes.sol";
import {IConfigurableVaultV1} from "../../../contracts/interfaces/internal/vault/extensions/configurable/IConfigurableVault.sol";

// Lyubo: Non owner tests
contract VaultConfigurableTest is VaultTestSuite {
    function test_SetConfig() public {
        vaultRegistry.setVaultConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.VaultConfig(address(0), 0, 0, address(0), address(0), address(0))
        );

        assertEq(address(vault.borrowVerifier()), address(0));
        assertEq(vault.withdrawFeeFactor(), 0);
        assertEq(vault.withdrawFeePeriod(), 0);
        assertEq(vault.configurableManager(), address(0));
        assertEq(vault.swapStrategy(), address(0));
        assertEq(vault.ingressControl(), address(0));
    }

    function test_WithdrawFeeFactorOutOfLimit() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultConfig(
            supplyAsset,
            borrowAsset,
            VaultTypes.VaultConfig(address(0), 100e18, 0, address(0), address(0), address(0))
        );
    }

    function test_SetBorrowLimits() public {
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(0, 0, 0)
        );

        assertEq(vault.supplyThreshold(), 0);
        assertEq(vault.targetThreshold(), 0);
        assertEq(vault.liquidationThreshold(), 0);
    }

    function test_SupplyThresholdOutOfLimit() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        // Supply threshold bigger than 1e18
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(100e18, 0, 0));

        // Supply threshold bigger than liquidation threhsold
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(7e17, 6e17, 0));
    }

    function test_TargetThresholdOutOfLimit() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        // Target threshold bigger than 1e18
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(0, 0, 100e18));

        // Target threshold bigger than liquidation threhsold
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(0, 6e17, 7e17));
    }

    function test_LiquidationThresholdOutOfLimit() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();

        // Liquidation threshold bigger than 1e18
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE.selector);
        vaultRegistry.setVaultBorrowLimits(supplyAsset, borrowAsset, VaultTypes.BorrowLimits(0, 100e18, 0));
    }

    function test_ReduceVaultTargetThreshold() public {
        vaultRegistry.reduceVaultTargetThreshold(deployer.supplyAsset(), deployer.borrowAsset(), 0);

        assertEq(vault.targetThreshold(), 0);
    }

    function test_ReduceVaultTargetThresholdWithHigherAmount() public {
        address supplyAsset = deployer.supplyAsset();
        address borrowAsset = deployer.borrowAsset();
        vm.expectRevert(IConfigurableVaultV1.VCONF_V1_TARGET_THRESHOLD_NOT_REDUCED.selector);
        vaultRegistry.reduceVaultTargetThreshold(supplyAsset, borrowAsset, 1e18);
    }

    function test_AllowOnBehalf() public {
        address[] memory allowance = new address[](1);
        allowance[0] = address(0);

        vault.allowOnBehalf(allowance, true);
        assertEq(vault.allowOnBehalfList(address(this), address(0)), true);
    }

    function test_DisableOnBehalf() public {
        bytes4[] memory functions = new bytes4[](1);
        functions[0] = 0x12345678;

        vaultRegistry.disableVaultOnBehalfValidation(deployer.supplyAsset(), deployer.borrowAsset(), functions, true);

        assertEq(vault.onBehalfFunctions(0x12345678), true);
    }
}
