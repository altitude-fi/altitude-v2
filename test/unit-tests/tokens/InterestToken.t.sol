// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {BaseGetter} from "../../base/BaseGetter.sol";
import {DebtToken} from "../../../contracts/tokens/DebtToken.sol";
import {CommonTypes} from "../../../contracts/libraries/types/CommonTypes.sol";

import {IInterestToken} from "../../../contracts/interfaces/internal/tokens/IInterestToken.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {IHarvestableVaultV1} from "../../../contracts/interfaces/internal/vault/extensions/harvestable/IHarvestableVault.sol";
import {ISnapshotableVaultV1} from "../../../contracts/interfaces/internal/vault/extensions/snapshotable/ISnapshotableVault.sol";

contract InterestTokenTest is Test {
    DebtToken public interestToken;

    address[] public users;
    address public lenderStrategy;
    address public underlyingAsset;

    function setUp() public {
        users = new address[](4);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");
        users[3] = makeAddr("user4");

        lenderStrategy = makeAddr("lenderStrategy");
        underlyingAsset = BaseGetter.getBaseERC20(6);

        // Deploy DebtToken as our test InterestToken implementation
        interestToken = new DebtToken();
        interestToken.initialize("debt", "debt", address(this), underlyingAsset, lenderStrategy, 1e20);

        // Mock vault functions
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IHarvestableVaultV1.getHarvestsCount.selector),
            abi.encode(1)
        );

        // Mock lender strategy functions
        vm.mockCall(lenderStrategy, abi.encodeWithSelector(ILenderStrategy.hasSupplyLoss.selector), abi.encode(false));
    }

    function test_Initialization() public view {
        assertEq(interestToken.decimals(), 6); // USDC decimals
        assertEq(interestToken.vault(), address(this));
        assertEq(interestToken.underlying(), underlyingAsset);
        assertEq(interestToken.activeLenderStrategy(), lenderStrategy);
    }

    function test_MintAndBurn() public {
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);
        _mockCalcCommit(users[0]);

        // Initial balance should be 0
        assertEq(interestToken.balanceOf(users[0]), 0);

        // Mint 10 tokens
        interestToken.mint(users[0], 10e18);
        _setBorrowBalance(10e18);
        _setBorrowPrincipal(10e18);
        _mockCalcCommit(users[0]);
        assertEq(interestToken.balanceOf(users[0]), 10e18);

        // Accrue interest (10 + 0.1)
        _setBorrowBalance(20.1e18);
        interestToken.snapshot();

        // Burn 5 tokens
        interestToken.burn(users[0], 5e18);
        _setBorrowPrincipal(15.1e18);
        _setBorrowBalance(15.1e18);

        // Mock harvesting earnings
        _mockCalcCommit(users[0], 0.3e18);
        assertApproxEqAbs(interestToken.balanceOf(users[0]), 14.8e18, 1);
    }

    function test_SetLenderStrategy() public {
        assertEq(interestToken.activeLenderStrategy(), lenderStrategy);

        address newStrategy = makeAddr("newStrategy");
        vm.mockCall(newStrategy, abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector), abi.encode(0));

        interestToken.setActiveLenderStrategy(newStrategy);

        assertEq(interestToken.activeLenderStrategy(), newStrategy);
        assertEq(interestToken.interestIndex(), interestToken.MATH_UNITS());
    }

    function test_RevertSetLenderStrategyUnauthorized() public {
        address newStrategy = makeAddr("newStrategy");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.setActiveLenderStrategy(newStrategy);
    }

    function test_SetBalanceIncrease() public {
        interestToken.mint(users[0], 10e18);
        interestToken.setBalance(users[0], 11e18, 1);
        assertEq(interestToken.balanceStored(users[0]), 11e18);
        assertEq(interestToken.userIndex(users[0]), 1);
    }

    function test_SetBalanceDecrease() public {
        interestToken.mint(users[0], 10e18);
        interestToken.setBalance(users[0], 9e18, 1);
        assertEq(interestToken.balanceStored(users[0]), 9e18);
        assertEq(interestToken.userIndex(users[0]), 1);
    }

    function test_SetInterestIndex() public {
        interestToken.setInterestIndex(1);
        assertEq(interestToken.interestIndex(), 1);
    }

    function test_SnapshotUserIncrease() public {
        interestToken.mint(users[0], 1e18);
        interestToken.setInterestIndex(interestToken.interestIndex() * 2);
        interestToken.snapshotUser(users[0]);
        assertEq(interestToken.balanceStored(users[0]), 2e18);
        assertEq(interestToken.userIndex(users[0]), interestToken.interestIndex());
    }

    function test_SnapshotUserDecrease() public {
        interestToken.mint(users[0], 1e18);
        interestToken.setInterestIndex(interestToken.interestIndex() / 2);
        interestToken.snapshotUser(users[0]);
        assertEq(interestToken.balanceStored(users[0]), 0.5e18);
        assertEq(interestToken.userIndex(users[0]), interestToken.interestIndex());
    }

    function test_VaultAccessRestrictions() public {
        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(unauthorized);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.mint(users[0], 100);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.burn(users[0], 100);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.vaultTransfer(users[0], users[1], 1);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.setInterestIndex(1);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.snapshotUser(users[0]);

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.snapshot();

        vm.expectRevert(IInterestToken.IT_ONLY_VAULT.selector);
        interestToken.setBalance(users[0], 1, 1);

        vm.stopPrank();
    }

    function test_VaultTransfer() public {
        uint256 amount = 7.5e18;
        interestToken.mint(users[0], amount);

        interestToken.vaultTransfer(users[0], users[1], amount);
        assertEq(interestToken.balanceStored(users[0]), 0);
        assertEq(interestToken.balanceStored(users[1]), amount);
    }

    function test_VaultTransferBetweenTheSameAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IInterestToken.IT_TRANSFER_BETWEEN_THE_SAME_ADDRESSES.selector));
        interestToken.vaultTransfer(users[0], users[0], 1);
    }

    function test_InterestDistributionScenario1() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);
        _mockCalcCommit(users[0]);

        // Initial state verification
        assertEq(interestToken.balanceOf(users[0]), 0);
        assertEq(interestToken.totalSupply(), 0);

        // users[0] mints 5 tokens
        interestToken.snapshot();
        interestToken.mint(users[0], 5e18);
        _setBorrowBalance(5e18);
        _setBorrowPrincipal(5e18);
        _mockCalcCommit(users[0]);

        assertEq(interestToken.balanceOf(users[0]), 5e18);
        assertEq(interestToken.totalSupply(), 5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%
        interestToken.snapshot();

        // users[1] mints 7.5 tokens
        interestToken.mint(users[0], 7.5e18);
        _setBorrowBalance(12.5e18);
        _setBorrowPrincipal(12.5e18);
        interestToken.snapshot();

        // Verify balances after second mint
        _mockCalcCommit(users[0]);
        assertEq(interestToken.balanceOf(users[0]), 12.5e18);
        assertEq(interestToken.totalSupply(), 12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        _setBorrowBalance(20.40117666e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]), 20.40117666e18);
        assertEq(interestToken.balanceOf(users[1]), 0);

        interestToken.snapshot();
        _setBorrowPrincipal(20.40117666e18);

        // users[1] borrows 5 tokens
        interestToken.mint(users[1], 5e18);
        _setBorrowBalance(25.40117666e18);
        _setBorrowPrincipal(25.40117666e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]), 20.40117666e18);
        assertEq(interestToken.balanceOf(users[1]), 5e18);

        assertEq(interestToken.totalSupply(), 25.40117666e18);

        // FLOW 4: T36 - T48 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(33.29664073e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]) / 1e14, 267424);
        assertEq(interestToken.balanceOf(users[1]) / 1e13, 655415);
    }

    function test_InterestDistributionScenario2() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);
        _mockCalcCommit(users[0]);

        // Initial state verification
        assertEq(interestToken.balanceOf(users[0]), 0);
        assertEq(interestToken.totalSupply(), 0);

        // users[0] mints 5 tokens
        interestToken.snapshot();
        interestToken.mint(users[0], 5e18);
        _setBorrowBalance(5e18);
        _setBorrowPrincipal(5e18);

        _mockCalcCommit(users[0]);

        assertEq(interestToken.balanceOf(users[0]), 5e18);
        assertEq(interestToken.totalSupply(), 5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%
        _mockCalcCommit(users[0]);

        // users[1] mints 7.5 tokens
        interestToken.mint(users[1], 7.5e18);
        _setBorrowBalance(12.5e18);
        _setBorrowPrincipal(12.5e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]), 5e18);
        assertEq(interestToken.balanceOf(users[1]), 7.5e18);
        assertEq(interestToken.totalSupply(), 12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        _setBorrowBalance(20.40117666e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]) / 1e13, 816047);
        assertEq(interestToken.balanceOf(users[1]) / 1e14, 122407);

        interestToken.snapshot();
        _setBorrowPrincipal(20.40117666e18);

        // users[2] borrows 4 tokens
        interestToken.mint(users[2], 4e18);
        _setBorrowBalance(24.40117666e18);
        _setBorrowPrincipal(24.40117666e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);
        _mockCalcCommit(users[2]);

        assertEq(interestToken.balanceOf(users[0]) / 1e13, 816047);
        assertEq(interestToken.balanceOf(users[1]) / 1e14, 122407);
        assertEq(interestToken.balanceOf(users[2]), 4e18);
        assertEq(interestToken.totalSupply(), 24.40117666e18);

        // FLOW 4: T36 - T48 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(33.29664073e18);
        interestToken.snapshot();
        _setBorrowPrincipal(33.29664073e18);

        // users[3] borrows 1 tokens
        interestToken.mint(users[3], 1e18);
        _setBorrowBalance(34.29664073e18);
        _setBorrowPrincipal(34.29664073e18);
        assertEq(interestToken.totalSupply(), 34.29664073e18);

        // FLOW 5: T48 - T60 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(54.34325197e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);
        _mockCalcCommit(users[2]);
        _mockCalcCommit(users[3]);

        assertEq(interestToken.balanceOf(users[0]) / 1e14, 176440);
        assertEq(interestToken.balanceOf(users[1]) / 1e14, 264661);
        assertEq(interestToken.balanceOf(users[2]) / 1e13, 864855);
        assertEq(interestToken.balanceOf(users[3]) / 1e13, 158450);
    }

    function test_InterestDistributionScenario3() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);

        // users[0] mints 5 tokens
        interestToken.snapshot();
        interestToken.mint(users[0], 5e18);
        _setBorrowBalance(5e18);
        _setBorrowPrincipal(5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%

        // users[1] mints 7.5 tokens
        interestToken.mint(users[1], 7.5e18);
        _setBorrowBalance(12.5e18);
        _setBorrowPrincipal(12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        _setBorrowBalance(20.40117666e18);
        interestToken.snapshot();
        _setBorrowPrincipal(20.40117666e18);

        // users[2] borrows 4 tokens
        interestToken.mint(users[2], 4e18);
        _setBorrowBalance(24.40117666e18);
        _setBorrowPrincipal(24.40117666e18);

        // FLOW 4: T36 - T48 (12 Months)
        // Interest Rate: 50%
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);
        _mockCalcCommit(users[2]);

        assertEq(interestToken.balanceOf(users[0]) / 1e13, 816047);
        assertEq(interestToken.balanceOf(users[1]) / 1e14, 122407);
        assertEq(interestToken.balanceOf(users[2]), 4e18);
    }

    function test_DropScenario1() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);

        // users[0] mints 5 tokens
        interestToken.snapshot();
        interestToken.mint(users[0], 5e18);
        _setBorrowBalance(5e18);
        _setBorrowPrincipal(5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%
        // users[1] mints 7.5 tokens
        interestToken.mint(users[1], 7.5e18);
        _setBorrowBalance(12.5e18);
        _setBorrowPrincipal(12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        // Total balance grows to 20.40117666
        _setBorrowBalance(20.40117666e18);
        interestToken.snapshot();
        _setBorrowPrincipal(20.40117666e18);

        // users[2] borrows 4 tokens
        interestToken.mint(users[2], 4e18);
        _setBorrowBalance(24.40117666e18);
        _setBorrowPrincipal(24.40117666e18);

        // FLOW 4: T36 - T48 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(39.82501725e18);
        interestToken.snapshot();
        _setBorrowPrincipal(39.82501725e18);

        // users[3] borrows 1 tokens
        interestToken.mint(users[3], 1e18);
        _setBorrowBalance(40.82501725e18);
        _setBorrowPrincipal(40.82501725e18);

        // FLOW 5: T48 - T60 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(66.63027112e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);
        _mockCalcCommit(users[2]);
        _mockCalcCommit(users[3]);

        assertEq(interestToken.balanceOf(users[0]) / 1e14, 217373);
        assertEq(interestToken.balanceOf(users[1]) / 1e14, 326059);
        assertEq(interestToken.balanceOf(users[2]) / 1e14, 106549);
        assertEq(interestToken.balanceOf(users[3]) / 1e13, 163209);

        // Drop happens (50%)
        // Total balance drops to 33.31513556
        _setBorrowBalance(33.315135561e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);
        _mockCalcCommit(users[2]);
        _mockCalcCommit(users[3]);

        assertEq(interestToken.interestIndex(), interestToken.calcNewIndex());

        assertEq(interestToken.balanceOf(users[0]) / 1e9, 13318656288);
        assertEq(interestToken.balanceOf(users[1]) / 1e9, 19977984432);
        assertEq(interestToken.balanceOf(users[2]) / 1e9, 6528376529);
        assertEq(interestToken.balanceOf(users[3]) / 1e7, 100000000000);
    }

    function test_DropScenario2() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);

        // users[0] mints 5 tokens
        interestToken.snapshot();
        interestToken.mint(users[0], 5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        interestToken.snapshot();

        // users[1] mints 7.5 tokens
        interestToken.mint(users[1], 7.5e18);
        _setBorrowBalance(12.5e18);
        interestToken.snapshot();
        _setBorrowPrincipal(12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        _setBorrowBalance(20.40117666e18);

        // Drop happens (50%)
        // Total balance drops to 10.20058833
        assertNotEq(interestToken.interestIndex(), interestToken.calcNewIndex());
        _setBorrowBalance(10.20058833e18);
        assertEq(interestToken.interestIndex(), interestToken.calcNewIndex());
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]) / 1e9, 5000000000);
        assertEq(interestToken.balanceOf(users[1]) / 1e9, 7500000000);
    }

    function test_DropScenario3() public {
        // FLOW 1: T0 - T12 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        _setBorrowPrincipal(0);
        interestToken.snapshot();

        // users[0] mints 5 tokens
        interestToken.mint(users[0], 5e18);

        // FLOW 2: T12 - T24 (12 Months)
        // Interest Rate: 50%
        _setBorrowBalance(0);
        interestToken.snapshot();

        // users[1] mints 7.5 tokens
        interestToken.mint(users[1], 7.5e18);
        _setBorrowBalance(12.5e18);
        interestToken.snapshot();
        _setBorrowPrincipal(12.5e18);

        // FLOW 3: T24 - T36 (12 Months)
        // Interest Rate: 20%
        _setBorrowBalance(20.40117666e18);

        // Drop happens (33%)
        // Total balance drops to 13.6687883622
        _setBorrowBalance(13.6687883622e18);
        _mockCalcCommit(users[0]);
        _mockCalcCommit(users[1]);

        assertEq(interestToken.balanceOf(users[0]) / 1e9, 5467515344);
        assertEq(interestToken.balanceOf(users[1]) / 1e9, 8201273017);
    }

    function _setBorrowBalance(uint256 amount) internal {
        vm.mockCall(lenderStrategy, abi.encodeWithSelector(ILenderStrategy.borrowBalance.selector), abi.encode(amount));
    }

    function _setBorrowPrincipal(uint256 amount) internal {
        vm.mockCall(
            lenderStrategy,
            abi.encodeWithSelector(ILenderStrategy.borrowPrincipal.selector),
            abi.encode(amount)
        );
    }

    function _mockCalcCommit(address user) internal {
        _mockCalcCommit(user, 0);
    }

    function _mockCalcCommit(address user, uint256 earnings) internal {
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ISnapshotableVaultV1.calcCommitUser.selector, user, type(uint256).max),
            abi.encode(
                0,
                0,
                0,
                0,
                earnings,
                0,
                CommonTypes.UserPosition(0, 0, interestToken.userIndex(user), interestToken.balanceStored(user))
            )
        );
    }
}
