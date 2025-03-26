// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../../../libraries/types/VaultTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface IVaultRegistryV1 {
    enum ManagingRoles {
        FUNCTIONS,
        FUNCTIONALITY,
        EMERGENCY
    }

    event SetManager(address manager, ManagingRoles role);
    event VaultDeployed(
        address vault,
        address indexed supplyAsset,
        address indexed borrowAsset,
        address supplyToken,
        address debtToken
    );

    event UpdateVaultConfig(
        address indexed vault,
        address configurableManager,
        address swapStrategy,
        address ingressControl,
        address borrowVerifier,
        uint256 withdrawFeeFactor,
        uint256 withdrawFeePeriod
    );
    event UpdateSnapshotableConfig(address indexed vault, address snapshotableManager, uint256 reserveFactor);
    event UpdateGroomableConfig(
        address indexed vault,
        address groomableManager,
        address flashLoanStrategy,
        uint256 maxMigrationFeePercentage
    );
    event UpdateLiquidationConfig(
        address indexed vault,
        address liquidatableManager,
        uint256 maxPositionLiquidation,
        uint256 liquidationBonus,
        uint256 minUsersToLiquidate,
        uint256 minRepayAmount
    );

    event UpdateBorrowLimits(
        address indexed vault,
        uint256 supplyThreshold,
        uint256 liquidationThreshold,
        uint256 targetThreshold
    );

    event DisableOnBehalfValidation(address indexed vault, bytes4[] functions, bool toDisable);
    event WithdrawnReserve(address indexed vault, address receiver, uint256 amount, uint256 amountWithdrawn);
    event InjectSupply(address indexed vault, uint256 amount);
    event UpdateProxyAdmin(address newProxyAdmin);
    event UpdateInitImpl(address newInitImpl);
    event UpdateTokensFactory(address newTokensFactory);
    event SetVaultReserveReceiver(address receiver);
    event ReduceTargetThreshold(address indexed vault, uint256 targetThreshold);

    // Vault Registry V1 Errors
    error VR_V1_ZERO_ADDRESS();
    error VR_V1_NONEXISTING_VAUlT();
    error VR_V1_NOT_EMERGENCY_MANAGER();
    error VR_V1_NOT_FUNCTIONS_MANAGER();
    error VR_V1_ALREADY_EXISTING_VAULT();
    error VR_V1_NOT_FUNCTIONALITY_MANAGER();

    function tokensFactory() external view returns (address);

    function vaultInitImpl() external view returns (address);

    function vaultInitCodeHash() external view returns (bytes32);

    function proxyAdmin() external view returns (address);

    function vaultsArray(uint256 index) external view returns (address);

    function vaults(address supplyAsset, address borrowAsset) external view returns (address);

    function initialize(VaultTypes.RegistryConfiguration memory config) external;

    function vaultAddress(address supplyAsset, address borrowAsset) external view returns (address);

    function vaultReserveReceiver() external view returns (address);

    function createVault(
        address supplyAsset,
        address borrowAsset,
        uint256 supplyMathUnits,
        uint256 debtMathUnits,
        address vaultLogic,
        VaultTypes.VaultData memory vaultData
    ) external;

    function harvestVault(address supplyAsset, address borrowAsset, uint256 price) external;

    function injectBorrowAssetsInVault(address supplyAsset, address borrowAsset, uint256 amount) external;

    function changeVaultLendingProvider(address supplyAsset, address borrowAsset, address newProvider) external;

    function changeVaultFarmDispatcher(address supplyAsset, address borrowAsset, address newFarmDispatcher) external;

    function setVaultConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.VaultConfig memory vaultConfig
    ) external;

    function setSnapshotableConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.SnapshotableConfig memory snapshotableConfig
    ) external;

    function setGroomableConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.GroomableConfig memory groomableConfig
    ) external;

    function setLiquidationConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.LiquidatableConfig memory liquidatableConfig
    ) external;

    function setVaultBorrowLimits(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.BorrowLimits memory borrowLimits
    ) external;

    function reduceVaultTargetThreshold(address supplyAsset, address borrowAsset, uint256 targetThreshold) external;

    function setProxyAdmin(address newProxyAdmin) external;

    function setInitImpl(address newInitImpl) external;

    function setTokensFactory(address newTokensFactory) external;

    function disableVaultOnBehalfValidation(
        address supplyAsset,
        address borrowAsset,
        bytes4[] memory functions,
        bool toDisable
    ) external;

    function setVaultReserveReceiver(address receiver) external;

    function withdrawVaultReserve(address supplyAsset, address borrowAsset, uint256 amount) external;

    function injectSupplyInVault(address supplyAsset, address borrowAsset, uint256 amount, uint256 index) external;

    function vaultsCount() external view returns (uint256);
}
