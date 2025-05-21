pragma solidity 0.8.28;

import "../../utils/VaultTestSuite.sol";

import {VaultTypes} from "../../../contracts/libraries/types/VaultTypes.sol";
import {TransferHelper} from "../../../contracts/libraries/uniswap-v3/TransferHelper.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {ILiquidatableManager} from "../../../contracts/interfaces/internal/vault/extensions/liquidatable/ILiquidatableManager.sol";

contract VaultLiquidatableTest is VaultTestSuite {
    uint256 public supplyRemaining; // expected supply remaining after liquidation
    uint256 public constant MAX_BORROW = 7e6; // Target threshold

    function setUp() public override {
        super.setUp();

        // The price is 1:1 and for 70 debt repaid 70 supply + bonus should be taken out
        (, , uint256 liquidationBonus) = vault.getLiquidationConfig();
        supplyRemaining = DEPOSIT - (7e18 + (7e18 * liquidationBonus) / 1e18);
    }

    function test_CheckIfUserForLiquidation() public {
        depositAndBorrow(vm.addr(1), DEPOSIT, MAX_BORROW);

        // Simulate the user is for liquidation
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(5e17, 5e17, 5e17)
        );

        assertEq(vault.isUserForLiquidation(vm.addr(1)), true);
    }

    function test_LiquidateUsers() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        vault.liquidateUsers(liquidationUsers, liquidationAmount);

        _assertValidLiquidation(0);
    }

    function test_LiquidateUsersSkipHealthyOnes() public {
        (, uint256 liquidationAmount) = _prepareLiquidation();

        // User 4 has no debt and is not for liquidation
        depositAndBorrow(vm.addr(4), DEPOSIT, 1e6);

        address[] memory allLiquidationUsers = new address[](4);
        allLiquidationUsers[0] = vm.addr(1);
        allLiquidationUsers[1] = vm.addr(2);
        allLiquidationUsers[2] = vm.addr(3);
        allLiquidationUsers[3] = vm.addr(4);

        vault.liquidateUsers(allLiquidationUsers, liquidationAmount);

        _assertValidLiquidation(1e6);
        assertEq(vault.debtToken().balanceOf(vm.addr(4)), 1e6);
        assertEq(vault.supplyToken().balanceOf(vm.addr(4)), DEPOSIT);
    }

    function test_LiquidateUsersWithSupplyLoss() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        // Simulate default positions
        vm.mockCall(
            vault.activeLenderStrategy(),
            abi.encodeWithSelector(ILenderStrategy.getInBase.selector, deployer.borrowAsset(), deployer.supplyAsset()),
            abi.encode(10 ** IToken(deployer.supplyAsset()).decimals() * 2) // make the price 2:1 for defaulting positions
        );

        vault.liquidateUsers(liquidationUsers, liquidationAmount);

        assertTrue(ILenderStrategy(vault.activeLenderStrategy()).borrowBalance() > 0);
        assertEq(vault.supplyToken().balanceOf(vm.addr(1)), 0);
        assertEq(vault.supplyToken().balanceOf(vm.addr(2)), 0);
        assertEq(vault.supplyToken().balanceOf(vm.addr(3)), 0);
        assertEq(vault.supplyToken().balanceOf(address(this)), DEPOSIT * 3);
    }

    function test_LiquidateUsersOverPay() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        // Obtain more tokens than needed
        mintToken(deployer.borrowAsset(), address(this), MAX_BORROW);
        IToken(deployer.borrowAsset()).approve(address(vault), MAX_BORROW * 4);

        vault.liquidateUsers(liquidationUsers, liquidationAmount + MAX_BORROW);

        _assertValidLiquidation(0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(address(this)), MAX_BORROW); // Amount returned back
    }

    function test_LiquidateUsersUpToLenderBorrowBalance() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        // Simulate the debt balance of a user to be slightly bigger than the borrow balance
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IToken.balanceOf.selector, vm.addr(1)),
            abi.encode(vault.debtToken().balanceOf(vm.addr(1)) + 1) // + 1 wei is enough
        );

        mintToken(deployer.borrowAsset(), address(this), 1); // Obtain 1 wei
        IToken(deployer.borrowAsset()).approve(address(vault), liquidationAmount + 1);
        vault.liquidateUsers(liquidationUsers, liquidationAmount + 1); // give 1 wei more

        // Reset the balance
        vm.mockCall(
            address(vault.debtToken()),
            abi.encodeWithSelector(IToken.balanceOf.selector, vm.addr(1)),
            abi.encode(0)
        );

        assertEq(ILenderStrategy(vault.activeLenderStrategy()).borrowBalance(), 0);
        assertEq(vault.debtToken().balanceOf(vm.addr(1)), 0);
        assertEq(vault.debtToken().balanceOf(vm.addr(2)), 0);
        assertEq(vault.debtToken().balanceOf(vm.addr(3)), 0);
        assertEq(IToken(deployer.borrowAsset()).balanceOf(address(this)), 1); // 1 wei being returned back
    }

    // Should liquidate users in case there is enough repay amount even though number of users has not been reached
    function test_LiquidateUsersByAmountNotByNumber() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        (address liquidatableManager, , ) = vault.getLiquidationConfig();
        vaultRegistry.setLiquidationConfig(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.LiquidatableConfig(liquidatableManager, 1e18, 1e16)
        );

        vault.liquidateUsers(liquidationUsers, liquidationAmount);

        _assertValidLiquidation(0);
    }

    // Should revert when liquidator does not have enough funds to cover the liquidation
    function test_LiquidateUsersWithoutHavingEnoughTokensToCover() public {
        (address[] memory liquidationUsers, uint256 liquidationAmount) = _prepareLiquidation();

        // User 4 has no debt and is not for liquidation
        depositAndBorrow(vm.addr(4), DEPOSIT, 1e6);

        address[] memory allLiquidationUsers = new address[](3);
        allLiquidationUsers[0] = vm.addr(1);
        allLiquidationUsers[1] = vm.addr(2);
        allLiquidationUsers[2] = vm.addr(3);
        allLiquidationUsers[2] = vm.addr(4);

        vm.expectRevert(TransferHelper.TH_SAFE_TRANSFER_FROM_FAILED.selector);
        vault.liquidateUsers(liquidationUsers, liquidationAmount + MAX_BORROW);
    }

    // Should revert when total repay amount is larger than repay amount limit
    function test_LiquidateUsersWithRepayAmountBiggerThanRepayLimit() public {
        (address[] memory liquidationUsers, ) = _prepareLiquidation();

        vm.expectRevert(ILiquidatableManager.LQ_V1_INSUFFICIENT_REPAY_AMOUNT.selector);
        vault.liquidateUsers(liquidationUsers, MAX_BORROW);
    }

    function _prepareLiquidation() internal returns (address[] memory, uint256) {
        address user1 = vm.addr(1);
        address user2 = vm.addr(2);
        address user3 = vm.addr(3);

        depositAndBorrow(user1, DEPOSIT, MAX_BORROW);
        depositAndBorrow(user2, DEPOSIT, MAX_BORROW);
        depositAndBorrow(user3, DEPOSIT, MAX_BORROW);

        // Simulate the users are for liquidation
        vaultRegistry.setVaultBorrowLimits(
            deployer.supplyAsset(),
            deployer.borrowAsset(),
            VaultTypes.BorrowLimits(6e17, 6e17, 6e17)
        );

        address[] memory liquidationUsers = new address[](3);
        liquidationUsers[0] = user1;
        liquidationUsers[1] = user2;
        liquidationUsers[2] = user3;

        // Obtain tokens for repaying positions
        mintToken(deployer.borrowAsset(), address(this), MAX_BORROW * 3);
        IToken(deployer.borrowAsset()).approve(address(vault), MAX_BORROW * 3);

        return (liquidationUsers, MAX_BORROW * 3);
    }

    function _assertValidLiquidation(uint256 expectedTotalBorrow) internal view {
        assertEq(ILenderStrategy(vault.activeLenderStrategy()).borrowBalance(), expectedTotalBorrow);
        assertEq(vault.debtToken().balanceOf(vm.addr(1)), 0);
        assertEq(vault.debtToken().balanceOf(vm.addr(2)), 0);
        assertEq(vault.debtToken().balanceOf(vm.addr(3)), 0);
        assertEq(vault.supplyToken().balanceOf(vm.addr(1)), supplyRemaining);
        assertEq(vault.supplyToken().balanceOf(vm.addr(2)), supplyRemaining);
        assertEq(vault.supplyToken().balanceOf(vm.addr(3)), supplyRemaining);
        assertEq(
            vault.supplyToken().balanceOf(address(this)),
            DEPOSIT * 3 - (supplyRemaining * 3) // liquidator supply balance
        );
    }
}
