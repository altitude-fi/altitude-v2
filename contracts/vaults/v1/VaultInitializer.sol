// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./base/VaultStorage.sol";
import "../../interfaces/internal/vault/IVaultCoreV1Initializer.sol";

/**
 * @title VaultCoreV1Initializer
 * @dev Inititialization of vault storage
 * @author Altitude Labs
 **/

contract VaultCoreV1Initializer is VaultStorage, IVaultCoreV1Initializer {
    /// @notice Initialize vault
    /// @param contractOwner Owner of the vault
    /// @param vaultData Vault configuration
    function initialize(address contractOwner, VaultTypes.VaultData memory vaultData) public override {
        _initializeConfigurableVaultV1(contractOwner, vaultData.vaultInit);
        _initializeGroomableVaultV1(vaultData.groomableConfig);
        _initializeLiquidatableVaultV1(vaultData.liquidatableConfig);
        _initializeSnapshotableVaultV1(vaultData.snapshotableConfig);
    }

    /// @notice Constructor of the contract
    /// @param contractOwner Owner of the vault
    /// @param vaultInit Vault configuration
    function _initializeConfigurableVaultV1(address contractOwner, VaultTypes.VaultInit memory vaultInit) internal {
        if (vaultInit.vaultConfig.withdrawFeeFactor > 1e18) {
            // 1e18 represents a 100%. withdrawFeeFactor is in percentage
            revert VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE();
        }
        if (
            vaultInit.borrowLimits.supplyThreshold > 1e18 ||
            vaultInit.borrowLimits.supplyThreshold > vaultInit.borrowLimits.liquidationThreshold
        ) {
            // 1e18 represents a 100%. supplyThreshold is in percentage
            revert VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE();
        }
        if (
            vaultInit.borrowLimits.targetThreshold > 1e18 ||
            vaultInit.borrowLimits.targetThreshold > vaultInit.borrowLimits.liquidationThreshold
        ) {
            // 1e18 represents a 100%. targetThreshold is in percentage
            revert VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE();
        }
        if (vaultInit.borrowLimits.liquidationThreshold >= 1e18) {
            // 1e18 represents a 100%. liquidationThreshold is in percentage
            revert VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE();
        }

        owner = contractOwner;

        swapStrategy = vaultInit.vaultConfig.swapStrategy;
        ingressControl = vaultInit.vaultConfig.ingressControl;
        borrowVerifier = IBorrowVerifier(vaultInit.vaultConfig.borrowVerifier);
        withdrawFeeFactor = vaultInit.vaultConfig.withdrawFeeFactor;
        withdrawFeePeriod = vaultInit.vaultConfig.withdrawFeePeriod;
        configurableManager = vaultInit.vaultConfig.configurableManager;

        targetThreshold = vaultInit.borrowLimits.targetThreshold;
        supplyThreshold = vaultInit.borrowLimits.supplyThreshold;
        liquidationThreshold = vaultInit.borrowLimits.liquidationThreshold;

        activeFarmStrategy = vaultInit.providers.farming;
        activeLenderStrategy = vaultInit.providers.lending;
    }

    /// @notice Setup groomable config
    /// @param config Groomable config
    function _initializeGroomableVaultV1(VaultTypes.GroomableConfig memory config) internal {
        if (config.maxMigrationFeePercentage > 1e18) {
            // 1e18 represents a 100%. maxMigrationFeePercentage is in percentage
            revert GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE();
        }

        groomableStorage = config;
    }

    /// @notice Setup users liquidation config
    /// @param config Users liquidation config
    function _initializeLiquidatableVaultV1(VaultTypes.LiquidatableConfig memory config) internal {
        if (config.liquidationBonus > 1e18) {
            // 1e18 represents a 100%. liquidationBonus is in percentage
            revert LQ_V1_MAX_BONUS_OUT_OF_RANGE();
        }

        if (config.maxPositionLiquidation > 1e18) {
            // 1e18 represents a 100%. maxPositionLiquidation is in percentage
            revert LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE();
        }

        liquidatableStorage = config;
    }

    /// @notice Setup snapshotable config
    /// @param config Snapshotable config
    function _initializeSnapshotableVaultV1(VaultTypes.SnapshotableConfig memory config) internal {
        if (config.reserveFactor > 1e18) {
            // 1e18 represents a 100%. reserveFactor is in percentage
            revert HV_V1_RESERVE_FACTOR_OUT_OF_RANGE();
        }

        HarvestTypes.HarvestData memory newHarvest;
        newHarvest.blockNumber = block.number;
        harvestStorage.harvests.push(newHarvest);
        harvestStorage.reserveFactor = config.reserveFactor;
        snapshotManager = config.snapshotableManager;
    }

    /// @notice Initialize vault tokens
    /// @param _supplyInterestToken supplyToken for the vault
    /// @param _borrowInterestToken debtToken for the vault
    function setTokens(address _supplyInterestToken, address _borrowInterestToken) public override {
        supplyToken = ISupplyToken(_supplyInterestToken);
        debtToken = IDebtToken(_borrowInterestToken);
        supplyUnderlying = supplyToken.underlying();
        borrowUnderlying = debtToken.underlying();

        emit SetTokens(_supplyInterestToken, _borrowInterestToken);
    }
}
