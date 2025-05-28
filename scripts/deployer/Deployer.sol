// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {Config} from "./Config.sol";
import {Constants} from "./Constants.sol";

import {IToken} from "../../test/interfaces/IToken.sol";

import {RolesGranter} from "./RolesGranter.sol";

// Generic
import {TokensFactory} from "../../contracts/tokens/TokensFactory.sol";
import {VaultRegistryV1} from "../../contracts/vaults/v1/VaultRegistry.sol";
import {FarmBufferDispatcher} from "../../contracts/strategies/farming/FarmBufferDispatcher.sol";
import {VaultCoreV1Initializer} from "../../contracts/vaults/v1/VaultInitializer.sol";

// Vault Oriented
import {VaultETH} from "../../contracts/vaults/v1/ETH/VaultETH.sol";
import {VaultERC20} from "../../contracts/vaults/v1/ERC20/VaultERC20.sol";
import {VaultTypes} from "../../contracts/libraries/types/VaultTypes.sol";
import {IVaultCoreV1} from "../../contracts/interfaces/internal/vault/IVaultCore.sol";

// Managers
import {GroomableManager} from "../../contracts/vaults/v1/extensions/groomable/GroomableManager.sol";
import {ConfigurableManager} from "../../contracts/vaults/v1/extensions/configurable/ConfigurableManager.sol";
import {LiquidatableManager} from "../../contracts/vaults/v1/extensions/liquidatable/LiquidatableManager.sol";
import {SnapshotableManager} from "../../contracts/vaults/v1/extensions/snapshotable/SnapshotableManager.sol";

// Miscellaneous
import {Roles} from "../../contracts/common/Roles.sol";
import {Ingress} from "../../contracts/access/Ingress.sol";
import {BorrowVerifier} from "../../contracts/misc/BorrowVerifier.sol";
import {ProxyInitializable} from "../../contracts/common/ProxyInitializable.sol";

// Tokens
import {DebtToken} from "../../contracts/tokens/DebtToken.sol";
import {SupplyToken} from "../../contracts/tokens/SupplyToken.sol";
import {FarmBufferDispatcher} from "../../contracts/strategies/farming/FarmBufferDispatcher.sol";
import {RebalanceIncentivesController} from "../../contracts/misc/incentives/rebalance/RebalanceIncentivesController.sol";

/**
 * @title Deployer
 * @dev Abstract contract for deploying and initializing the protocol
 * @author Altitude Labs
 **/
abstract contract Deployer is Config {
    address internal deployerSender;

    address public borrowVerifier;
    address public vaultInitImpl;
    address public configurableManager;
    address public liquidatableManager;
    address public groomableManager;
    address public snapshotableManager;
    address public farmDispatcherImpl;
    address public vaultETHImpl;
    address public vaultERC20Impl;

    // Token implementations
    address public debtTokenImpl;
    address public supplyTokenImpl;

    /// @notice Initializes the deployer
    /// @param signer The address of the signer
    /// @param grandAdmin The address of the grand admin
    function initDeployer(address signer, address grandAdmin) public {
        super.initConfig(grandAdmin);
        deployerSender = signer;
    }

    /// @notice Returns the address of the vault core implementation.
    /// @return address of the vault core implementation.
    function _vaultCoreImpl() internal returns (address) {
        address addr;
        if (this.isERC20Vault()) {
            if (vaultERC20Impl == address(0)) {
                vaultERC20Impl = address(new VaultERC20());
            }
            addr = vaultERC20Impl;
        } else {
            if (vaultETHImpl == address(0)) {
                vaultETHImpl = address(new VaultETH());
            }
            addr = vaultETHImpl;
        }
        console.log("VaultCoreImpl, vaultCoreImpl, %s", addr);
        return addr;
    }

    /// @notice Returns the address of the vault initializer implementation.
    /// @return address of the vault initializer implementation.
    function _vaultInitImpl() internal returns (address) {
        if (vaultInitImpl == address(0)) {
            vaultInitImpl = address(new VaultCoreV1Initializer());
        }
        console.log("VaultCoreV1Initializer, vaultInitImpl, %s", vaultInitImpl);

        return vaultInitImpl;
    }

    /// @notice Returns the address of the borrow verifier implementation.
    /// @return address of the borrow verifier implementation.
    function _borrowVerifier(address vault) internal returns (address) {
        address addr = address(new BorrowVerifier(vault));
        console.log("BorrowVerifier, borrowVerifier, %s", addr);
        return addr;
    }

    /// @notice Returns the address of the configurable manager implementation.
    /// @return address of the configurable manager implementation.
    function _configurableManager() internal returns (address) {
        if (configurableManager == address(0)) {
            configurableManager = address(new ConfigurableManager());
        }
        console.log("ConfigurableManager, configurableManager, %s", configurableManager);

        return configurableManager;
    }

    /// @notice Returns the address of the liquidatable manager implementation.
    /// @return address of the liquidatable manager implementation.
    function _liquidatableManager() internal returns (address) {
        if (liquidatableManager == address(0)) {
            liquidatableManager = address(new LiquidatableManager());
        }
        console.log("LiquidatableManager, liquidatableManager, %s", liquidatableManager);

        return liquidatableManager;
    }

    /// @notice Returns the address of the groomable manager implementation.
    /// @return address of the groomable manager implementation.
    function _groomableManager() internal returns (address) {
        if (groomableManager == address(0)) {
            groomableManager = address(new GroomableManager());
        }
        console.log("GroomableManager, groomableManager, %s", groomableManager);

        return groomableManager;
    }

    /// @notice Returns the address of the snapshotable manager implementation.
    /// @return address of the snapshotable manager implementation.
    function _snapshotableManager() internal returns (address) {
        if (snapshotableManager == address(0)) {
            snapshotableManager = address(new SnapshotableManager());
        }
        console.log("SnapshotableManager, snapshotableManager, %s", snapshotableManager);

        return snapshotableManager;
    }

    function _farmDispatcherImpl() internal returns (address) {
        if (farmDispatcherImpl == address(0)) {
            farmDispatcherImpl = address(new FarmBufferDispatcher());
        }
        console.log("FarmBufferDispatcher, farmDispatcherImpl, %s", farmDispatcherImpl);

        return farmDispatcherImpl;
    }

    /// @notice Returns the address of the debt token implementation.
    /// @return address of the debt token implementation.
    function _debtTokenImpl() internal returns (address) {
        if (debtTokenImpl == address(0)) {
            debtTokenImpl = address(new DebtToken());
        }
        console.log("DebtToken, debtTokenImpl, %s", debtTokenImpl);

        return debtTokenImpl;
    }

    /// @notice Returns the address of the supply token implementation.
    /// @return address of the supply token implementation.
    function _supplyTokenImpl() internal returns (address) {
        if (supplyTokenImpl == address(0)) {
            supplyTokenImpl = address(new SupplyToken());
        }
        console.log("SupplyToken, supplyTokenImpl, %s", supplyTokenImpl);

        return supplyTokenImpl;
    }

    /// @notice Deploys the default protocol components.
    /// @return vaultRegistry The address of the deployed vault registry.
    function deployDefaultProtocol() public virtual returns (VaultRegistryV1 vaultRegistry) {
        ProxyInitializable vaultRegistryProxy = new ProxyInitializable();
        console.log("ProxyInitializable, vaultRegistryV1Proxy, %s", address(vaultRegistryProxy));
        vaultRegistry = new VaultRegistryV1();
        console.log("VaultRegistryV1, vaultRegistry, %s", address(vaultRegistry));

        address tokensFactory = _tokensFactory(
            this.GRAND_ADMIN(),
            this.UPGRADABILITY_EXECUTOR(),
            address(vaultRegistryProxy)
        );

        vaultRegistryProxy.initialize(
            this.UPGRADABILITY_EXECUTOR(),
            address(vaultRegistry),
            abi.encodeWithSignature(
                "initialize((address,address,address,address))",
                VaultTypes.RegistryConfiguration(
                    deployerSender,
                    tokensFactory, // tokensFactory
                    _vaultInitImpl(),
                    this.UPGRADABILITY_EXECUTOR()
                )
            )
        );

        vaultRegistry = VaultRegistryV1(address(vaultRegistryProxy));

        RolesGranter._grantRoles(address(vaultRegistryProxy), this);

        // Role required for deploying vaults and setting reserve receiver
        vaultRegistry.grantRole(Roles.BETA, deployerSender);
        vaultRegistry.setVaultReserveReceiver(this.RESERVE_RECEIVER());

        // Check grand admin to not revoke admin access
        if (this.GRAND_ADMIN() != deployerSender) {
            // Update roles
            vaultRegistry.grantRole(vaultRegistry.DEFAULT_ADMIN_ROLE(), this.GRAND_ADMIN());
        }
    }

    /// @notice Deploys the tokens factory.
    /// @param admin The address of the admin (owner).
    /// @param proxyAdmin The address of the proxy admin.
    /// @param registry The address of the registry.
    /// @return address of the deployed tokens factory.
    function _tokensFactory(address admin, address proxyAdmin, address registry) internal returns (address) {
        address tokensFactory = address(new TokensFactory(proxyAdmin));
        console.log("TokensFactory, tokensFactory, %s", tokensFactory);

        TokensFactory(tokensFactory).setRegistry(address(registry));
        TokensFactory(tokensFactory).setDebtTokenImplementation(_debtTokenImpl());
        TokensFactory(tokensFactory).setSupplyTokenImplementation(_supplyTokenImpl());
        TokensFactory(tokensFactory).transferOwnership(admin);

        return tokensFactory;
    }

    /// @notice Deploys the default vault.
    /// @param registry The address of the vault registry.
    /// @return address of the deployed vault.
    function deployDefaultVault(VaultRegistryV1 registry) public virtual returns (IVaultCoreV1) {
        return
            deployDefaultVault(
                registry,
                _constructVaultData(registry.vaultAddress(this.supplyAsset(), this.borrowAsset()))
            );
    }

    function deployDefaultVault(
        VaultRegistryV1 registry,
        VaultTypes.VaultData memory vaultData
    ) public virtual returns (IVaultCoreV1) {
        address vaultAddress = registry.vaultAddress(this.supplyAsset(), this.borrowAsset());

        // Registry should have granted deployer a role to create vaults beforehand
        registry.createVault(
            this.supplyAsset(),
            this.borrowAsset(),
            this.SUPPLY_MATH_UNITS(),
            this.BORROW_MATH_UNITS(),
            _vaultCoreImpl(),
            vaultData
        );
        address vaultActual = registry.vaults(this.supplyAsset(), this.borrowAsset());
        assert(vaultAddress == vaultActual); // expect computed == actual
        console.log("VaultCoreV1, vault, %s", vaultActual);

        return IVaultCoreV1(vaultActual);
    }

    /// @notice Constructs the vault data.
    /// @param vault The address of the vault.
    /// @return constructed vault data.
    function _constructVaultData(address vault) internal returns (VaultTypes.VaultData memory) {
        address farmDispatcher = _farmDispatcher(vault);
        address lenderStrategy = _lenderStrategy(vault, farmDispatcher);

        return
            VaultTypes.VaultData(
                VaultTypes.VaultInit(
                    VaultTypes.VaultConfig(
                        _borrowVerifier(vault),
                        this.WITHDRAW_FEE_FACTOR(),
                        this.WITHDRAW_FEE_PERIOD(),
                        _configurableManager(),
                        _swapStrategy(),
                        _ingressController(vault)
                    ),
                    VaultTypes.BorrowLimits(
                        this.SUPPLY_THRESHOLD(),
                        this.LIQUIDATION_THRESHOLD(),
                        this.TARGET_THRESHOLD()
                    ),
                    VaultTypes.DefiProviders(lenderStrategy, farmDispatcher)
                ),
                VaultTypes.LiquidatableConfig(
                    _liquidatableManager(),
                    this.MAX_POSITION_LIQUIDATION(),
                    this.LIQUIDATION_BONUS()
                ),
                VaultTypes.GroomableConfig(
                    _groomableManager(),
                    _flashLoanStrategy(),
                    this.MAX_MIGRATION_FEE_PERCENTAGE()
                ),
                VaultTypes.SnapshotableConfig(_snapshotableManager(), this.RESERVE_FACTOR())
            );
    }

    /// @notice Deploys the ingress controller.
    /// @param vault The address of the vault.
    /// @return address of the deployed ingress controller.
    function _ingressController(address vault) internal returns (address) {
        address[] memory sanctionedList;

        Ingress ingressController = new Ingress(
            deployerSender,
            sanctionedList,
            this.USER_MIN_DEPOSIT_LIMIT(),
            this.USER_MAX_DEPOSIT_LIMIT(),
            this.VAULT_MAX_DEPOSIT_LIMIT(),
            [this.WITHDRAW_RATE_LIMIT(), this.BORROW_RATE_LIMIT(), this.CLAIM_RATE_LIMIT()],
            [this.WITHDRAW_RATE_AMOUNT(), this.BORROW_RATE_AMOUNT(), this.CLAIM_RATE_AMOUNT()]
        );
        console.log("Ingress, ingressController, %s", address(ingressController));

        RolesGranter._grantRoles(address(ingressController), this);

        // Vault to be able to pause itself (supply loss)
        ingressController.grantRole(Roles.GAMMA, vault);

        // RebalanceIncentivesController to be able to rebalance
        ingressController.grantRole(Roles.GAMMA, _rebalanceIncentivesController(vault));

        // Check grand admin to not revoke entire admin access
        if (this.GRAND_ADMIN() != deployerSender) {
            // Transfer the admin role
            ingressController.grantRole(ingressController.DEFAULT_ADMIN_ROLE(), this.GRAND_ADMIN());

            ingressController.revokeRole(ingressController.DEFAULT_ADMIN_ROLE(), deployerSender);
        }

        return address(ingressController);
    }

    /// @notice Deploys the farm dispatcher.
    /// @param vault The address of the vault.
    /// @return address of the deployed farm dispatcher.
    function _farmDispatcher(address vault) internal returns (address) {
        ProxyInitializable proxyDispatcher = new ProxyInitializable();
        console.log("ProxyInitializable, proxyDispatcher, %s", address(proxyDispatcher));

        proxyDispatcher.initialize(
            this.UPGRADABILITY_EXECUTOR(),
            _farmDispatcherImpl(),
            abi.encodeWithSignature("initialize(address,address,address)", vault, this.borrowAsset(), deployerSender)
        );

        FarmBufferDispatcher farmDispatcher = FarmBufferDispatcher(address(proxyDispatcher));

        // Add strategies
        farmDispatcher.grantRole(Roles.ALPHA, deployerSender);
        address[] memory strategies = _farmStrategies(address(farmDispatcher));
        for (uint256 i = 1; i < strategies.length; i++) {
            farmDispatcher.addStrategy(strategies[i], this.CAPS(i - 1), strategies[i - 1]);
        }
        farmDispatcher.revokeRole(
            Roles.ALPHA, // Remove deployerSender roles
            deployerSender
        );

        // Load buffer [Tokens are to be transferred beforehand]
        if (this.BUFFER_SIZE() > 0) {
            farmDispatcher.grantRole(Roles.BETA, deployerSender);
            IToken(this.borrowAsset()).approve(address(farmDispatcher), this.BUFFER_SIZE());
            farmDispatcher.increaseBufferSize(this.BUFFER_SIZE());
            farmDispatcher.revokeRole(
                Roles.BETA, // Remove deployerSender roles
                deployerSender
            );
        }

        // Grant/Revoke roles
        RolesGranter._grantRoles(address(farmDispatcher), this);
        farmDispatcher.grantRole(
            Roles.GAMMA, // Grant Gamma role to the vault for dispatching
            vault
        );

        // Check grand admin to not revoke entire admin access
        if (this.GRAND_ADMIN() != deployerSender) {
            farmDispatcher.grantRole(
                farmDispatcher.DEFAULT_ADMIN_ROLE(),
                this.GRAND_ADMIN() // Grant grand admin role
            );
            farmDispatcher.revokeRole(farmDispatcher.DEFAULT_ADMIN_ROLE(), deployerSender);
        }

        return address(farmDispatcher);
    }

    /// @notice Deploys the rebalance incentives controller.
    /// @param vault The address of the vault.
    /// @return address of the deployed rebalance incentives controller.
    function _rebalanceIncentivesController(address vault) internal returns (address) {
        RebalanceIncentivesController rebalanceIncentivesController = new RebalanceIncentivesController(
            this.REBALANCE_INCENTIVE_REWARD_TOKEN(),
            vault,
            this.REBALANCE_MIN_DEVIATION(),
            this.REBALANCE_MAX_DEVIATION()
        );
        console.log(
            "RebalanceIncentivesController, rebalanceIncentivesController, %s",
            address(rebalanceIncentivesController)
        );

        rebalanceIncentivesController.transferOwnership(Constants.account_BETA);
        return address(rebalanceIncentivesController);
    }
}
