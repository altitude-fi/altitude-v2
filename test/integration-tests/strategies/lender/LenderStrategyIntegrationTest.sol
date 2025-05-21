// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";
import {ForkTest} from "../../../ForkTest.sol";
import {ILenderStrategy} from "../../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";

abstract contract LenderStrategyIntegrationTest is ForkTest, TokensGenerator {
    ILenderStrategy public lenderStrategy;
    address public vault;
    IERC20Metadata public supplyAsset;
    IERC20Metadata public borrowAsset;
    uint256 public constant MAX_DEPOSIT_FEE = 100;

    uint256 public DEPOSIT;
    uint256 public BORROW;

    function setUp() public override {
        super.setUp();

        _setUp();

        // Mint some supplyAsset to the vault
        mintToken(address(supplyAsset), vault, DEPOSIT * 10);
    }

    function _deposit(uint256 amount) internal virtual {
        vm.startPrank(vault);
        supplyAsset.transfer(address(lenderStrategy), amount);
        lenderStrategy.deposit(amount);
        vm.stopPrank();
    }

    function test_Deposit() public {
        assertEq(lenderStrategy.supplyBalance(), 0);
        _deposit(DEPOSIT);
        assertApproxEqRel(lenderStrategy.supplyBalance(), DEPOSIT, 0.005e18);
    }

    function test_Borrow() public {
        assertEq(lenderStrategy.borrowBalance(), 0);
        _deposit(DEPOSIT);

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        vm.stopPrank();

        assertApproxEqRel(lenderStrategy.borrowBalance(), BORROW, 0.005e18);
    }

    function test_Repay() public {
        assertEq(lenderStrategy.borrowBalance(), 0);
        _deposit(DEPOSIT);
        uint256 REPAY = BORROW / 2;

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        borrowAsset.approve(address(lenderStrategy), REPAY);
        lenderStrategy.repay(REPAY);
        vm.stopPrank();

        assertApproxEqRel(lenderStrategy.borrowBalance(), BORROW - REPAY, 0.005e18);
    }

    function test_RepayTooMuch() public {
        assertEq(lenderStrategy.borrowBalance(), 0);
        _deposit(DEPOSIT);
        uint256 REPAY = BORROW * 2;
        mintToken(address(borrowAsset), vault, REPAY);

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        borrowAsset.approve(address(lenderStrategy), REPAY);
        lenderStrategy.repay(REPAY);
        vm.stopPrank();

        assertApproxEqRel(lenderStrategy.borrowBalance(), 0, 0.005e18);
    }

    function test_Withdraw() public {
        assertEq(lenderStrategy.supplyBalance(), 0);
        _deposit(DEPOSIT);

        uint256 WITHDRAW = DEPOSIT / 2;

        vm.startPrank(vault);
        lenderStrategy.withdraw(WITHDRAW);
        vm.stopPrank();

        assertApproxEqRel(lenderStrategy.supplyBalance(), DEPOSIT - WITHDRAW, 0.005e18);
    }

    function test_WithdrawAll() public {
        assertEq(lenderStrategy.supplyBalance(), 0);
        _deposit(DEPOSIT);

        vm.startPrank(vault);
        lenderStrategy.withdrawAll();
        vm.stopPrank();

        assertEq(lenderStrategy.supplyBalance(), 0);
    }

    function test_WithdrawTooMuch() public {
        assertEq(lenderStrategy.supplyBalance(), 0);
        _deposit(DEPOSIT);

        vm.prank(vault);
        vm.expectRevert(ILenderStrategy.LS_WITHDRAW_INSUFFICIENT.selector);
        lenderStrategy.withdraw(DEPOSIT * 2);
    }

    function test_getInBase() public view {
        assertEq(
            _priceSupplyInBorrow(10 ** supplyAsset.decimals()),
            lenderStrategy.getInBase(address(supplyAsset), address(borrowAsset))
        );
    }

    function test_convertToBase() public view {
        uint256 amount = 150 * 10 ** supplyAsset.decimals();
        assertEq(
            _priceSupplyInBorrow(amount),
            lenderStrategy.convertToBase(amount, address(supplyAsset), address(borrowAsset))
        );
    }

    function test_recogniseRewardsInBase() public {
        assertEq(lenderStrategy.rewardsRecipient(), vault);
        uint256 before = borrowAsset.balanceOf(vault);
        address[] memory rewardsList = new address[](2);
        rewardsList[0] = BaseGetter.getBaseERC20(18);
        rewardsList[1] = BaseGetter.getBaseERC20(18);
        _accumulateRewards(rewardsList);
        lenderStrategy.recogniseRewardsInBase();
        uint256 rewards = borrowAsset.balanceOf(vault) - before;
        assertEq(rewards, 200 * (10 ** borrowAsset.decimals()), "Receive rewards");
    }

    function test_availableBorrowLiquidity() public {
        uint256 REPAY = BORROW / 2;

        _deposit(DEPOSIT);

        uint256 before = lenderStrategy.availableBorrowLiquidity();
        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        vm.stopPrank();

        assertEq(before - BORROW, lenderStrategy.availableBorrowLiquidity());

        vm.startPrank(vault);
        borrowAsset.approve(address(lenderStrategy), REPAY);
        lenderStrategy.repay(REPAY);
        vm.stopPrank();

        assertEq(before - BORROW + REPAY, lenderStrategy.availableBorrowLiquidity());
    }

    function test_supplyBalance() public {
        assertEq(lenderStrategy.supplyBalance(), 0);
        uint256 balance;
        _deposit(DEPOSIT);
        balance += DEPOSIT;
        assertEq(balance, lenderStrategy.supplyBalance());

        _deposit(DEPOSIT / 2);
        balance += DEPOSIT / 2;
        assertEq(balance, lenderStrategy.supplyBalance());

        vm.startPrank(vault);
        lenderStrategy.withdraw(DEPOSIT / 3);
        vm.stopPrank();

        balance -= DEPOSIT / 3;
        assertEq(balance, lenderStrategy.supplyBalance());

        vm.startPrank(vault);
        lenderStrategy.withdraw(DEPOSIT);
        vm.stopPrank();

        balance -= DEPOSIT;
        assertEq(balance, lenderStrategy.supplyBalance());

        vm.startPrank(vault);
        lenderStrategy.withdrawAll();
        vm.stopPrank();

        assertEq(0, lenderStrategy.supplyBalance());
    }

    function test_borrowBalance() public {
        _deposit(DEPOSIT * 5);

        assertEq(lenderStrategy.borrowBalance(), 0);
        uint256 balance;

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        vm.stopPrank();
        balance += BORROW;
        // balance rounds up 1 wei
        assertApproxEqAbs(balance, lenderStrategy.borrowBalance(), 1);

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW / 2);
        vm.stopPrank();
        balance += BORROW / 2;
        assertApproxEqAbs(balance, lenderStrategy.borrowBalance(), 1);

        vm.startPrank(vault);
        borrowAsset.approve(address(lenderStrategy), type(uint256).max);
        lenderStrategy.repay(BORROW / 3);
        vm.stopPrank();

        balance -= BORROW / 3;
        assertApproxEqAbs(balance, lenderStrategy.borrowBalance(), 1);

        vm.startPrank(vault);
        lenderStrategy.repay(BORROW);
        vm.stopPrank();

        balance -= BORROW;
        assertApproxEqAbs(balance, lenderStrategy.borrowBalance(), 1);

        vm.startPrank(vault);
        lenderStrategy.repay(borrowAsset.balanceOf(address(vault)));
        vm.stopPrank();
        balance = 0;
        assertApproxEqAbs(balance, lenderStrategy.borrowBalance(), 1);
    }

    function _setUp() internal virtual;

    function _accumulateRewards(address[] memory rewardsList) internal virtual;

    function _priceSupplyInBorrow(uint256 amount) internal view virtual returns (uint256);
}
