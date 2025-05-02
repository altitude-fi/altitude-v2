// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title VaultTypes
 * @dev Input parameters for not having "Stack too deep"
 * @author Altitude Labs
 **/

library VaultTypes {
    /// @notice RegistryConfiguration parameters
    struct RegistryConfiguration {
        address registryAdmin; // global registry admin used to grant roles/access
        address tokensFactory; // tokens factory implementation
        address vaultInitImpl; // vault init implementation
        address proxyAdmin; // proxy admin implementation
    }

    /// @notice Vault BorrowLimit configuration parameters
    struct BorrowLimits {
        uint256 supplyThreshold; // loan-to-value up to which the user can borrow
        uint256 liquidationThreshold; // loan-to-value after which the user can be liquidated
        uint256 targetThreshold; // loan-to-value the vault targets to rebalance to
    }

    /// @notice Vault DefiProviders configuration parameters
    struct DefiProviders {
        address lending; // address of lending provider
        address farming; // address of farming provider
    }

    /// @notice Vault configuration parameters
    struct SnapshotableConfig {
        address snapshotableManager; // snapshotable manager implementation
        uint256 reserveFactor; // percentage of earnings to be allocated to the reserve
    }

    /// @notice Vault configuration parameters
    struct VaultConfig {
        address borrowVerifier; // borrow verifier implementation
        uint256 withdrawFeeFactor; // percentage of the withdraw fee
        uint256 withdrawFeePeriod; // number of blocks the withdraw fee is applied
        address configurableManager; // configurable manager implementation
        address swapStrategy; // swap strategy implementation
        address ingressControl; // ingress control implementation
    }

    /// @notice Vault Liquidation configuration parameters
    struct LiquidatableConfig {
        address liquidatableManager; // liquidatable manager implementation
        uint256 maxPositionLiquidation; // The maximum liquidation allowed by the contract, 18 decimals
        uint256 liquidationBonus; // The supply bonus that will be received by the liquidator, 18 decimals
    }

    /// @notice Vault Groomable configuration parameters
    struct GroomableConfig {
        address groomableManager; // groomable manager implementation
        address flashLoanStrategy; // flash loan strategy implementation
        uint256 maxMigrationFeePercentage; // a fixed percentage to check if the given flash loan strategy charges higher fees than we expect
    }

    /// @notice Vault Init configuration parameters
    struct VaultInit {
        VaultConfig vaultConfig; // vault configuration
        BorrowLimits borrowLimits; // borrow limits
        DefiProviders providers; // defi providers
    }

    /// @notice Vault Data parameters
    struct VaultData {
        VaultInit vaultInit; // vault init configuration
        LiquidatableConfig liquidatableConfig; // liquidatable configuration
        GroomableConfig groomableConfig; // groomable configuration
        SnapshotableConfig snapshotableConfig; // snapshotable configuration
    }
}
