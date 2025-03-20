// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {BaseGetter} from "../../base/BaseGetter.sol";

import {SupplyToken} from "../../../contracts/tokens/SupplyToken.sol";
import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";

import {ISupplyToken} from "../../../contracts/interfaces/internal/tokens/ISupplyToken.sol";
import {IInterestToken} from "../../../contracts/interfaces/internal/tokens/IInterestToken.sol";
import {IVaultCoreV1} from "../../../contracts/interfaces/internal/vault/IVaultCore.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {ISnapshotableVaultV1} from "../../../contracts/interfaces/internal/vault/extensions/snapshotable/ISnapshotableVault.sol";

contract SupplyTokenTest is Test {
    SupplyToken public supplyToken;

    address[] public users;
    address public lenderStrategy;

    function setUp() public {
        users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");
        lenderStrategy = makeAddr("lenderStrategy");

        // Deploy SupplyToken
        supplyToken = new SupplyToken();
        supplyToken.initialize("supply", "supply", address(this), BaseGetter.getBaseERC20(18), lenderStrategy, 1e20);

        // Mock vault functions
        vm.mockCall(address(this), abi.encodeWithSelector(IVaultCoreV1.preTransfer.selector), abi.encode());
        vm.mockCall(address(this), abi.encodeWithSelector(IVaultCoreV1.postTransfer.selector), abi.encode());
    }

    function test_TransferBetweenAccounts() public {
        uint256 newSupplyBalance = 7.5e18;

        // Mint initial tokens
        supplyToken.mint(users[0], newSupplyBalance);
        _setSupplyPrincipal(newSupplyBalance);

        // Accrue interest
        newSupplyBalance = 12.240706e18;
        _setSupplyBalance(newSupplyBalance);

        supplyToken.snapshot();
        _setSupplyPrincipal(newSupplyBalance);

        // Mint more tokens
        supplyToken.mint(users[1], 12.5e18);
        newSupplyBalance = 24.740706e18;
        _setSupplyPrincipal(newSupplyBalance);

        // Accrue interest
        newSupplyBalance = 30.16859633e18;
        _setSupplyBalance(newSupplyBalance);

        supplyToken.snapshot();
        _setSupplyPrincipal(newSupplyBalance);
        _mockCalcCommit();

        vm.prank(users[0]);
        supplyToken.transfer(users[1], 14.926207769018757186e18);
        _mockCalcCommit();

        assertEq(supplyToken.balanceOf(users[0]), 0);
        assertEq(supplyToken.balanceOf(users[1]), 30.168596330000000001e18);
    }

    function test_TransferOnBehalfOfAnotherAccount() public {
        _setSupplyBalance(0);
        uint256 newSupplyBalance = 7.5e18;

        supplyToken.mint(users[0], newSupplyBalance);

        vm.prank(users[0]);
        supplyToken.approve(users[1], 8e18);

        _setSupplyBalance(newSupplyBalance);
        _setSupplyPrincipal(newSupplyBalance);
        _mockCalcCommit();

        vm.prank(users[1]);
        supplyToken.transferFrom(users[0], users[1], newSupplyBalance);
        _mockCalcCommit();

        assertEq(supplyToken.balanceOf(users[0]), 0);
        assertEq(supplyToken.balanceOf(users[1]), newSupplyBalance);
    }

    function test_TransferMaxAmount() public {
        uint256 amount = 5e18;

        supplyToken.mint(users[0], amount);
        _setSupplyBalance(amount);
        _setSupplyPrincipal(amount);

        supplyToken.mint(users[1], amount);
        _setSupplyBalance(amount * 2);
        _setSupplyPrincipal(amount * 2);

        _mockCalcCommit();

        vm.prank(users[0]);
        supplyToken.transferMax(users[2]);
        _mockCalcCommit();

        vm.prank(users[1]);
        supplyToken.approve(users[2], type(uint256).max);

        vm.prank(users[2]);
        supplyToken.transferFromMax(users[1], users[2]);

        _mockCalcCommit();
        assertEq(supplyToken.balanceOf(users[2]), amount * 2);
    }

    function test_TransferMaxAmountWithNoAllowance() public {
        uint256 amount = 10e18;

        supplyToken.mint(users[0], amount);
        _setSupplyBalance(amount);
        _setSupplyPrincipal(amount);

        _mockCalcCommit();

        vm.expectRevert(abi.encodeWithSelector(ISupplyToken.ST_NOT_ENOUGH_ALLOWANCE.selector));
        supplyToken.transferFrom(users[0], users[1], amount);

        vm.prank(users[0]);
        supplyToken.approve(users[1], 1e18);

        vm.expectRevert(abi.encodeWithSelector(ISupplyToken.ST_NOT_ENOUGH_ALLOWANCE.selector));
        supplyToken.transferFromMax(users[0], users[1]);
    }

    function test_TransferToZeroAddress() public {
        supplyToken.mint(users[0], 10);
        _setSupplyBalance(10);
        _setSupplyPrincipal(10);

        _mockCalcCommit();

        vm.expectRevert("ERC20: transfer to the zero address");
        supplyToken.transfer(address(0), 0);
    }

    function test_ApproveZeroAddress() public {
        vm.expectRevert("ERC20: approve to the zero address");
        supplyToken.approve(address(0), 10);
    }

    function test_MintZeroAddress() public {
        vm.expectRevert("ERC20: mint to the zero address");
        supplyToken.mint(address(0), 10);
    }

    function test_BurnFromZeroAddress() public {
        vm.expectRevert("ERC20: burn from the zero address");
        supplyToken.burn(address(0), 10);
    }

    function test_BalanceOfAtCalculation() public {
        supplyToken.mint(users[0], 7e6);

        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector, users[0], 0),
            abi.encode(0, 0, 0, 0, 0, 0, CommonTypes.UserPosition(102040816326530612244, 75e7, 0, 0))
        );

        assertEq(supplyToken.balanceOfAt(users[0], 0), 75e7);
    }

    function test_TransferFromNotEnoughBalance() public {
        _setSupplyBalance(0);
        _setSupplyPrincipal(0);
        _mockCalcCommit();
        vm.expectRevert(abi.encodeWithSelector(ISupplyToken.ST_NOT_ENOUGH_BALANCE.selector));
        supplyToken.transferFrom(users[0], users[1], 10);
    }

    function test_TransferFromNotEnoughAllowance() public {
        supplyToken.mint(users[0], 10e18);

        vm.prank(users[0]);
        supplyToken.approve(users[1], 1e18);

        _setSupplyBalance(10e18);
        _setSupplyPrincipal(10e18);
        _mockCalcCommit();

        vm.prank(users[1]);
        vm.expectRevert(abi.encodeWithSelector(ISupplyToken.ST_NOT_ENOUGH_ALLOWANCE.selector));
        supplyToken.transferFrom(users[0], users[1], 10e18);
    }

    function test_TransferNotEnoughBalance() public {
        _setSupplyBalance(0);
        _setSupplyPrincipal(0);
        _mockCalcCommit();
        vm.expectRevert(abi.encodeWithSelector(ISupplyToken.ST_NOT_ENOUGH_BALANCE.selector));
        supplyToken.transfer(users[1], 10);
    }

    function test_BalanceOfVault() public view {
        assertEq(supplyToken.balanceOf(address(this)), 0);
    }

    function _setSupplyBalance(uint256 amount) internal {
        vm.mockCall(lenderStrategy, abi.encodeWithSelector(ILenderStrategy.supplyBalance.selector), abi.encode(amount));
    }

    function _setSupplyPrincipal(uint256 amount) internal {
        vm.mockCall(
            lenderStrategy,
            abi.encodeWithSelector(ILenderStrategy.supplyPrincipal.selector),
            abi.encode(amount)
        );
    }

    function _mockCalcCommit() internal {
        for (uint256 i = 0; i < users.length; i++) {
            vm.mockCall(
                address(this),
                abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector, users[i], type(uint256).max),
                abi.encode(
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    CommonTypes.UserPosition(supplyToken.userIndex(users[i]), supplyToken.balanceStored(users[i]), 0, 0)
                )
            );
        }
    }
}
