// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deployer} from "../scripts/deployer/Deployer.sol";

import {BaseGetter} from "./base/BaseGetter.sol";

import {Roles} from "../contracts/common/Roles.sol";
import {IIngress} from "../contracts/interfaces/internal/access/IIngress.sol";
import {IVaultCoreV1} from "../contracts/interfaces/internal/vault/IVaultCore.sol";
import {IFarmDispatcher} from "../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";
import {VaultRegistryV1} from "../contracts/vaults/v1/VaultRegistry.sol";

// Test purposes only
contract TestDeployer is Deployer, Test {
    bool public constant override isERC20Vault = true;

    // vm.addr(1) = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf
    address public constant override UPGRADABILITY_EXECUTOR = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
    address public constant override RESERVE_RECEIVER = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;

    uint256 public constant override USER_MIN_DEPOSIT_LIMIT = 0;
    uint256 public constant override USER_MAX_DEPOSIT_LIMIT = 100e18;
    uint256 public constant override VAULT_MAX_DEPOSIT_LIMIT = 100e18;

    // Rate Limits & Amounts
    uint256 public constant override WITHDRAW_RATE_LIMIT = 0;
    uint256 public constant override WITHDRAW_RATE_AMOUNT = 0;
    uint256 public constant override BORROW_RATE_LIMIT = 0;
    uint256 public constant override BORROW_RATE_AMOUNT = 0;
    uint256 public constant override CLAIM_RATE_LIMIT = 0;
    uint256 public constant override CLAIM_RATE_AMOUNT = 0;

    // Vault
    uint256 public constant override WITHDRAW_FEE_FACTOR = 0;
    uint256 public constant override WITHDRAW_FEE_PERIOD = 0;
    uint256 public constant override SUPPLY_THRESHOLD = 0.7e18; // 70%
    uint256 public constant override LIQUIDATION_THRESHOLD = 0.8e18; // 80%
    uint256 public constant override TARGET_THRESHOLD = 0.7e18; // 70%
    uint256 public constant override MAX_POSITION_LIQUIDATION = 1e18; // 100%
    uint256 public constant override LIQUIDATION_BONUS = 0.01e18; // 1%
    uint256 public constant override MAX_MIGRATION_FEE_PERCENTAGE = 1e18; // 100%
    uint256 public constant override RESERVE_FACTOR = 0.25e18; // 25%

    // Incentives
    uint256 public constant override REBALANCE_MIN_DEVIATION = 0.10e18; // 10% deviation below target
    uint256 public constant override REBALANCE_MAX_DEVIATION = 0.10e18; // 10% deviation above target
    address public constant override REBALANCE_INCENTIVE_REWARD_TOKEN = address(0);

    // Tokens
    uint256 public constant override SUPPLY_MATH_UNITS = 1e18;
    uint256 public constant override BORROW_MATH_UNITS = 1e18;
    address private _supplyAsset;
    address private _borrowAsset;

    // Roles
    uint256 public override ALPHA_ROLE_LENGTH = 1;
    uint256 public override BETA_ROLE_LENGTH = 1;
    uint256 public override GAMMA_ROLE_LENGTH = 1;
    // vm.addr(1) = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf
    address[] public override ALPHA_ROLE = [0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf];
    address[] public override BETA_ROLE = [0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf];
    address[] public override GAMMA_ROLE = [0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf];

    // Farm strategies [First cap is always for the zero strategy]
    uint256 public constant override BUFFER_SIZE = 0;
    uint256[] public override CAPS = [0];

    // Providers
    address private _swapProvider;
    address private _priceProvider;
    address private _lenderProvider;
    address private _flashLoanProvider;

    function supplyAsset() public override returns (address) {
        if (_supplyAsset == address(0)) {
            _supplyAsset = BaseGetter.getBaseERC20(18);
        }
        return _supplyAsset;
    }

    function borrowAsset() public override returns (address) {
        if (_borrowAsset == address(0)) {
            _borrowAsset = BaseGetter.getBaseERC20(6);
        }
        return _borrowAsset;
    }

    // Function for overriding default tokens addresses. Use before deployment
    function setTokens(address supplyAddr, address borrowAddr) public {
        _supplyAsset = supplyAddr;
        _borrowAsset = borrowAddr;
    }

    function _lenderStrategy(address vaultAddress, address farmDispatcher) internal override returns (address) {
        if (_lenderProvider == address(0)) {
            _lenderProvider = BaseGetter.getBaseLenderStrategy(
                vaultAddress,
                supplyAsset(),
                borrowAsset(),
                farmDispatcher,
                _priceSource()
            );
        }
        return _lenderProvider;
    }

    function _swapStrategy() internal override returns (address) {
        if (_swapProvider == address(0)) {
            _swapProvider = BaseGetter.getBaseSwapStrategy(_priceSource());
        }
        return _swapProvider;
    }

    function _priceSource() internal override returns (address) {
        if (_priceProvider == address(0)) {
            _priceProvider = BaseGetter.getBasePriceSource();
        }
        return _priceProvider;
    }

    function _flashLoanStrategy() internal override returns (address) {
        if (_flashLoanProvider == address(0)) {
            _flashLoanProvider = BaseGetter.getBaseFlashLoanStrategy();
        }
        return _flashLoanProvider;
    }

    function swapProvider() public view returns (address) {
        return _swapProvider;
    }

    function priceProvider() public view returns (address) {
        return _priceProvider;
    }

    function lenderProvider() public view returns (address) {
        return _lenderProvider;
    }

    function flashLoanProvider() public view returns (address) {
        return _flashLoanProvider;
    }

    function _farmStrategies(address) internal pure override returns (address[] memory) {
        address[] memory strategies = new address[](1);
        // Always starts from zero strategy
        strategies[0] = address(0);
        return strategies;
    }

    function deployDefaultProtocol() public virtual override returns (VaultRegistryV1 vaultRegistry) {
        vaultRegistry = super.deployDefaultProtocol();

        vm.startPrank(this.GRAND_ADMIN());
        // Allow msg.sender(contract with tests) to execute config transactions
        vaultRegistry.grantRole(Roles.ALPHA, msg.sender);
        vaultRegistry.grantRole(Roles.BETA, msg.sender);
        vaultRegistry.grantRole(Roles.GAMMA, msg.sender);

        // Allow contract with tests to execute vault deployments
        vaultRegistry.grantRole(Roles.BETA, address(this));
        vm.stopPrank();
    }

    function deployDefaultVault(VaultRegistryV1 registry) public virtual override returns (IVaultCoreV1 vault) {
        vault = super.deployDefaultVault(registry);

        // Disable allowlist validation
        vm.mockCall(vault.ingressControl(), abi.encodeWithSelector(IIngress.validateDeposit.selector), abi.encode());

        vm.startPrank(this.GRAND_ADMIN());
        // Allow msg.sender(contract with tests) to execute rebalance transactions
        IIngress(vault.ingressControl()).grantRole(Roles.ALPHA, msg.sender);
        IIngress(vault.ingressControl()).grantRole(Roles.BETA, msg.sender);
        IIngress(vault.ingressControl()).grantRole(Roles.GAMMA, msg.sender);

        // Allow msg.sender(contract with tests) to manage the dispatcher as well
        IFarmDispatcher(vault.activeFarmStrategy()).grantRole(Roles.ALPHA, msg.sender);
        IFarmDispatcher(vault.activeFarmStrategy()).grantRole(Roles.BETA, msg.sender);
        IFarmDispatcher(vault.activeFarmStrategy()).grantRole(Roles.GAMMA, msg.sender);
        vm.stopPrank();

        // Return max available to execute rebalance
        vm.mockCall(
            vault.activeFarmStrategy(),
            abi.encodeWithSelector(IFarmDispatcher.availableLimit.selector),
            abi.encode(type(uint256).max)
        );
    }
}
