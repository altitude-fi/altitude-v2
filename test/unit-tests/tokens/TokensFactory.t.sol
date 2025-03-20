// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {TokensFactory} from "../../../contracts/tokens/TokensFactory.sol";
import {SupplyToken} from "../../../contracts/tokens/SupplyToken.sol";
import {DebtToken} from "../../../contracts/tokens/DebtToken.sol";

import {BaseGetter} from "../../base/BaseGetter.sol";
import {Constants} from "../../../scripts/deployer/Constants.sol";

import {IInterestToken} from "../../../contracts/interfaces/internal/tokens/IInterestToken.sol";
import {ITokensFactory} from "../../../contracts/interfaces/internal/tokens/ITokensFactory.sol";

contract TokensFactoryTest is Test {
    TokensFactory public tokensFactory;
    address public proxyAdmin;
    address public registry;
    address public vault;
    address public lenderStrategy;

    function setUp() public {
        proxyAdmin = makeAddr("proxyAdmin");
        registry = makeAddr("registry");
        vault = makeAddr("vault");
        lenderStrategy = makeAddr("lenderStrategy");

        tokensFactory = new TokensFactory(proxyAdmin);
    }

    function test_CorrectInitialization() public view {
        assertEq(tokensFactory.proxyAdmin(), proxyAdmin);
    }

    function test_InitializationZeroAddress() public {
        vm.expectRevert(ITokensFactory.TF_ZERO_ADDRESS.selector);
        new TokensFactory(address(0));
    }

    function test_SetRegistry() public {
        tokensFactory.setRegistry(registry);
        assertEq(tokensFactory.registry(), registry);
    }

    function test_SetRegistryUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        tokensFactory.setRegistry(registry);
    }

    function test_SetSupplyTokenImplementation() public {
        address implementation = address(new SupplyToken());
        tokensFactory.setSupplyTokenImplementation(implementation);
        assertEq(tokensFactory.supplyTokenImplementation(), implementation);
    }

    function test_SetSupplyTokenImplementationUnauthorized() public {
        address implementation = address(new SupplyToken());
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        tokensFactory.setSupplyTokenImplementation(implementation);
    }

    function test_SetDebtTokenImplementation() public {
        address implementation = address(new DebtToken());
        tokensFactory.setDebtTokenImplementation(implementation);
        assertEq(tokensFactory.debtTokenImplementation(), implementation);
    }

    function test_SetDebtTokenImplementation_Unauthorized() public {
        address implementation = address(new DebtToken());
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        tokensFactory.setDebtTokenImplementation(implementation);
    }

    function test_SetProxyAdmin() public {
        address newProxyAdmin = makeAddr("newProxyAdmin");
        tokensFactory.setProxyAdmin(newProxyAdmin);
        assertEq(tokensFactory.proxyAdmin(), newProxyAdmin);
    }

    function test_SetProxyAdminZeroAddress() public {
        vm.expectRevert(ITokensFactory.TF_ZERO_ADDRESS.selector);
        tokensFactory.setProxyAdmin(address(0));
    }

    function test_SetProxyAdminUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        tokensFactory.setProxyAdmin(makeAddr("newProxyAdmin"));
    }

    function test_CreatePair() public {
        // Setup implementations
        tokensFactory.setSupplyTokenImplementation(address(new SupplyToken()));
        tokensFactory.setDebtTokenImplementation(address(new DebtToken()));
        tokensFactory.setRegistry(registry);

        address supplyAsset = BaseGetter.getBaseERC20Detailed(6, "Supply Token", "SUP");
        address borrowAsset = BaseGetter.getBaseERC20Detailed(18, "Borrow Token", "BRW");

        vm.startPrank(registry);

        (address supplyToken, address debtToken) = tokensFactory.createPair(
            vault,
            supplyAsset,
            borrowAsset,
            6, // Supply token decimals
            18, // Borrow token decimals
            lenderStrategy
        );

        // Verify supply token
        assertEq(IInterestToken(supplyToken).vault(), vault);
        assertEq(IInterestToken(supplyToken).underlying(), supplyAsset);
        assertEq(IInterestToken(supplyToken).activeLenderStrategy(), lenderStrategy);
        assertEq(IInterestToken(supplyToken).decimals(), 6);
        assertEq(IInterestToken(supplyToken).name(), "Altitude Ethereum SUPBRW v1 Supply Token");
        assertEq(IInterestToken(supplyToken).symbol(), "ALTISUPBRWv1S");

        // Verify debt token
        assertEq(IInterestToken(debtToken).vault(), vault);
        assertEq(IInterestToken(debtToken).underlying(), borrowAsset);
        assertEq(IInterestToken(debtToken).activeLenderStrategy(), lenderStrategy);
        assertEq(IInterestToken(debtToken).decimals(), 18);
        assertEq(IInterestToken(debtToken).name(), "Altitude Ethereum SUPBRW v1 Debt Token");
        assertEq(IInterestToken(debtToken).symbol(), "ALTISUPBRWv1D");

        vm.stopPrank();
    }

    function test_CreatePairUnauthorized() public {
        vm.expectRevert(ITokensFactory.TF_ONLY_REGISTRY.selector);
        tokensFactory.createPair(vault, address(0), address(0), 1e6, 1e18, lenderStrategy);
    }
}
