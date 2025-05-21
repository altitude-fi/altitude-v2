// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../libraries/types/VaultTypes.sol";
import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/vault/IVaultCore.sol";
import "../../interfaces/internal/vault/IVaultCoreV1Initializer.sol";
import "../../interfaces/internal/vault/IVaultRegistry.sol";
import "../../interfaces/internal/vault/extensions/liquidatable/ILiquidatableVault.sol";
import "../../interfaces/internal/tokens/ITokensFactory.sol";
import "../../common/Roles.sol";
import "../../common/ProxyInitializable.sol";

/**
 * @title VaultRegistryV1
 * @dev Contract responsible for Creating, Managing & Configuring vaults
 * @dev Each vault represents a unique `supplyAsset` <-> `borrowAsset` pair
 * @author Altitude Labs
 **/

contract VaultRegistryV1 is AccessControl, Initializable, IVaultRegistryV1 {
    address public override tokensFactory;

    /** @notice vault initialization implementations */
    address public override vaultInitImpl;

    /** @notice vault initialization code hash */
    bytes32 public constant override vaultInitCodeHash =
        keccak256(abi.encodePacked(type(ProxyInitializable).creationCode));

    /** @notice address allowed to upgrade vaults */
    address public override proxyAdmin;

    /** @notice address to receive vault fees */
    address public override vaultReserveReceiver;

    /** @notice for FrontEnd convinience */
    address[] public override vaultsArray;

    /** @notice Available vaults (ETH -> [ USDC -> Vault ]) */
    mapping(address => mapping(address => address)) public override vaults;

    /** @notice Check if a vault already exists for the token pair */
    modifier onlyNotExisingVault(address supplyAsset, address borrowAsset) {
        _onlyNotExisingVault(supplyAsset, borrowAsset);
        _;
    }

    /// @notice Check that a vault already exists for the token pair
    /// @param supplyAsset vault supply asset
    /// @param borrowAsset vault borrow asset
    modifier onlyExistingVault(address supplyAsset, address borrowAsset) {
        _onlyExistingVault(supplyAsset, borrowAsset);
        _;
    }

    function initialize(VaultTypes.RegistryConfiguration calldata config) external override initializer {
        if (
            config.tokensFactory == address(0) ||
            config.vaultInitImpl == address(0) ||
            config.proxyAdmin == address(0) ||
            config.registryAdmin == address(0)
        ) {
            revert VR_V1_ZERO_ADDRESS();
        }

        tokensFactory = config.tokensFactory;
        vaultInitImpl = config.vaultInitImpl;
        proxyAdmin = config.proxyAdmin;

        _grantRole(DEFAULT_ADMIN_ROLE, config.registryAdmin);
    }

    function vaultAddress(address supplyAsset, address borrowAsset) external view override returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                address(this),
                                keccak256(abi.encodePacked(supplyAsset, borrowAsset)),
                                vaultInitCodeHash
                            )
                        )
                    )
                )
            );
    }

    /// @notice Deploys a new Vault for `erc20 supply asset` <-> `erc20 borrow asset` pair
    /// @param supplyAsset The address of supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param vaultCoreImpl The address of the vault core implementation
    /// @param vaultData Vault configuration params
    function createVault(
        address supplyAsset,
        address borrowAsset,
        uint256 supplyMathUnits,
        uint256 debtMathUnits,
        address vaultCoreImpl,
        VaultTypes.VaultData memory vaultData
    ) external override onlyRole(Roles.BETA) onlyNotExisingVault(supplyAsset, borrowAsset) {
        bytes32 salt = keccak256(abi.encodePacked(supplyAsset, borrowAsset));
        ProxyInitializable vaultProxy = new ProxyInitializable{salt: salt}();
        vaultProxy.initialize(
            address(this),
            vaultInitImpl,
            abi.encodeWithSelector(IVaultCoreV1Initializer.initialize.selector, address(this), vaultData)
        );

        _setupVault(
            address(vaultProxy),
            vaultCoreImpl,
            supplyAsset,
            borrowAsset,
            supplyMathUnits,
            debtMathUnits,
            vaultData.vaultInit.providers.lending
        );
    }

    /// @notice Perform some validations and set SupplyToken and DebtToken of the vault
    /// @param vault The newly deployed vault
    /// @param vaultCoreImpl The core logic of the vault
    /// @param supplyAsset The asset to supply
    /// @param borrowAsset The asset to borrow
    /// @param lenderStrategy The active lender strategy of the vault
    function _setupVault(
        address vault,
        address vaultCoreImpl,
        address supplyAsset,
        address borrowAsset,
        uint256 supplyMathUnits,
        uint256 debtMathUnits,
        address lenderStrategy
    ) internal {
        (address supplyToken, address debtToken) = ITokensFactory(tokensFactory).createPair(
            vault,
            supplyAsset,
            borrowAsset,
            supplyMathUnits,
            debtMathUnits,
            lenderStrategy
        );

        IVaultCoreV1Initializer(vault).setTokens(supplyToken, debtToken);
        ProxyInitializable(payable(vault)).upgradeTo(vaultCoreImpl);
        ProxyInitializable(payable(vault)).changeAdmin(proxyAdmin);

        vaultsArray.push(vault);
        vaults[supplyAsset][borrowAsset] = vault;

        emit VaultDeployed(vault, supplyAsset, borrowAsset, supplyToken, debtToken);
    }

    /// @notice Updates the external contracts for the vault
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param config vault external contracts
    function setVaultConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.VaultConfig memory config
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).setConfig(
            config.configurableManager,
            config.swapStrategy,
            config.ingressControl,
            config.borrowVerifier,
            config.withdrawFeeFactor,
            config.withdrawFeePeriod
        );

        emit UpdateVaultConfig(
            vaults[supplyAsset][borrowAsset],
            config.configurableManager,
            config.swapStrategy,
            config.ingressControl,
            config.borrowVerifier,
            config.withdrawFeeFactor,
            config.withdrawFeePeriod
        );
    }

    /// @notice Updates the limit parameters of a vault
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param config Reserve factor and harvest limit
    function setSnapshotableConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.SnapshotableConfig memory config
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).setSnapshotableConfig(config);

        emit UpdateSnapshotableConfig(
            vaults[supplyAsset][borrowAsset],
            config.snapshotableManager,
            config.reserveFactor
        );
    }

    /// @notice Updates the groomable parameters
    /// @param supplyAsset The address of supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param groomableConfig groomable config
    function setGroomableConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.GroomableConfig memory groomableConfig
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).setGroomableConfig(groomableConfig);

        emit UpdateGroomableConfig(
            vaults[supplyAsset][borrowAsset],
            groomableConfig.groomableManager,
            groomableConfig.flashLoanStrategy,
            groomableConfig.maxMigrationFeePercentage
        );
    }

    /// @notice Updates the liquidation config
    /// @param supplyAsset The address of supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param liquidatableConfig liquidation config
    function setLiquidationConfig(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.LiquidatableConfig memory liquidatableConfig
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).setLiquidationConfig(liquidatableConfig);

        emit UpdateLiquidationConfig(
            vaults[supplyAsset][borrowAsset],
            liquidatableConfig.liquidatableManager,
            liquidatableConfig.maxPositionLiquidation,
            liquidatableConfig.liquidationBonus
        );
    }

    /// @notice Updates the limit parameters of a vault
    /// @param supplyAsset The address of supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param borrowLimits Borrow limits per vault and user
    function setVaultBorrowLimits(
        address supplyAsset,
        address borrowAsset,
        VaultTypes.BorrowLimits memory borrowLimits
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).setBorrowLimits(
            borrowLimits.supplyThreshold,
            borrowLimits.liquidationThreshold,
            borrowLimits.targetThreshold
        );

        emit UpdateBorrowLimits(
            vaults[supplyAsset][borrowAsset],
            borrowLimits.supplyThreshold,
            borrowLimits.liquidationThreshold,
            borrowLimits.targetThreshold
        );
    }

    /// @notice Reduce target threshold to reduce the risk of vault being liquidated
    /// @param supplyAsset The address of supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param targetThreshold The new target threshold
    function reduceVaultTargetThreshold(
        address supplyAsset,
        address borrowAsset,
        uint256 targetThreshold
    ) external override onlyRole(Roles.GAMMA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).reduceTargetThreshold(targetThreshold);

        emit ReduceTargetThreshold(vaults[supplyAsset][borrowAsset], targetThreshold);
    }

    /// @notice Set who can upgrade vaults implementation
    /// @param newProxyAdmin The address allowed to upgrade vaults
    function setProxyAdmin(address newProxyAdmin) external override onlyRole(Roles.ALPHA) {
        if (newProxyAdmin == address(0)) {
            revert VR_V1_ZERO_ADDRESS();
        }

        proxyAdmin = newProxyAdmin;
        emit UpdateProxyAdmin(newProxyAdmin);
    }

    /// @notice Set the config implementation for all of the vaults
    /// @param newInitImpl The address the new implementation
    function setInitImpl(address newInitImpl) external override onlyRole(Roles.BETA) {
        if (newInitImpl == address(0)) {
            revert VR_V1_ZERO_ADDRESS();
        }

        vaultInitImpl = newInitImpl;
        emit UpdateInitImpl(newInitImpl);
    }

    /// @notice Set the tokens factory
    /// @param newTokensFactory The address the new implementation
    function setTokensFactory(address newTokensFactory) external override onlyRole(Roles.BETA) {
        if (newTokensFactory == address(0)) {
            revert VR_V1_ZERO_ADDRESS();
        }

        tokensFactory = newTokensFactory;
        emit UpdateTokensFactory(newTokensFactory);
    }

    /// @notice Initiate harvest of a vault
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param price For harvest execution requirements
    function harvestVault(
        address supplyAsset,
        address borrowAsset,
        uint256 price
    ) external override onlyRole(Roles.GAMMA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).harvest(price);
    }

    /// @notice Deposit funds directly into the farm to cover any rewards deficit in a restricted way
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param amount Borrow amount to be injected
    function injectBorrowAssetsInVault(
        address supplyAsset,
        address borrowAsset,
        uint256 amount
    ) external override onlyRole(Roles.GAMMA) onlyExistingVault(supplyAsset, borrowAsset) {
        TransferHelper.safeTransferFrom(borrowAsset, msg.sender, address(this), amount);
        TransferHelper.safeApprove(borrowAsset, vaults[supplyAsset][borrowAsset], amount);

        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).injectBorrowAssets(amount);
    }

    /// @notice Move to a new lending provider in the vault
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param newProvider The provider to be migrated to
    function changeVaultLendingProvider(
        address supplyAsset,
        address borrowAsset,
        address newProvider
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).migrateLender(newProvider);
    }

    /// @notice Move to a new farm dispatcher contract
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param newFarmDispatcher The new FarmDispatcher contract
    function changeVaultFarmDispatcher(
        address supplyAsset,
        address borrowAsset,
        address newFarmDispatcher
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).migrateFarmDispatcher(newFarmDispatcher);
    }

    /// @notice Disable on behalf validation for a list of functions
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param functions The list of functions to disable on behalf validation for
    /// @param toDisable The state of the on behalf validation
    /// @dev This should only be applied if an upgrade removes risks related to this
    function disableVaultOnBehalfValidation(
        address supplyAsset,
        address borrowAsset,
        bytes4[] memory functions,
        bool toDisable
    ) external override onlyRole(Roles.ALPHA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).disableOnBehalfValidation(functions, toDisable);

        emit DisableOnBehalfValidation(vaults[supplyAsset][borrowAsset], functions, toDisable);
    }

    /// @notice Set address which is to receive vault reserve amount
    /// @param receiver The address the fees will be transferred to
    function setVaultReserveReceiver(address receiver) external override onlyRole(Roles.BETA) {
        if (receiver == address(0)) {
            revert VR_V1_ZERO_ADDRESS();
        }

        vaultReserveReceiver = receiver;
        emit SetVaultReserveReceiver(receiver);
    }

    /// @notice Withdraw from the protocol reserve
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param amount The amount of fees to be transferred
    function withdrawVaultReserve(
        address supplyAsset,
        address borrowAsset,
        uint256 amount
    ) external override onlyRole(Roles.BETA) onlyExistingVault(supplyAsset, borrowAsset) {
        if (vaultReserveReceiver == address(0)) {
            revert VR_V1_ZERO_ADDRESS();
        }

        uint256 amountWithdrawn = IVaultCoreV1(vaults[supplyAsset][borrowAsset]).withdrawReserve(
            vaultReserveReceiver,
            amount
        );

        emit WithdrawnReserve(vaults[supplyAsset][borrowAsset], vaultReserveReceiver, amount, amountWithdrawn);
    }

    /// @notice Inject supply in the vault in case of supply loss
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    /// @param amount The amount of fees to be transferred
    function injectSupplyInVault(
        address supplyAsset,
        address borrowAsset,
        uint256 amount,
        uint256 index
    ) external override onlyRole(Roles.GAMMA) onlyExistingVault(supplyAsset, borrowAsset) {
        IVaultCoreV1(vaults[supplyAsset][borrowAsset]).injectSupply(amount, index, msg.sender);

        emit InjectSupply(vaults[supplyAsset][borrowAsset], amount);
    }

    /// @notice Get the current vaults count (used by FE)
    function vaultsCount() external view override returns (uint256) {
        return vaultsArray.length;
    }

    // -------- Internal functions --------

    /// @notice Check if the vault already exists
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    function _onlyNotExisingVault(address supplyAsset, address borrowAsset) internal view {
        if (vaults[supplyAsset][borrowAsset] != address(0)) {
            revert VR_V1_ALREADY_EXISTING_VAULT();
        }
    }

    /// @notice Confirm the vault already exists
    /// @param supplyAsset The address of the supply asset
    /// @param borrowAsset The address of the borrow asset
    function _onlyExistingVault(address supplyAsset, address borrowAsset) internal view {
        if (vaults[supplyAsset][borrowAsset] == address(0)) {
            revert VR_V1_NONEXISTING_VAUlT();
        }
    }
}
