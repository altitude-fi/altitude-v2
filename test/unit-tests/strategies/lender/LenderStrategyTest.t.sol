pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import {BaseLenderStrategy} from "../../../base/BaseLenderStrategy.sol";
import {ILenderStrategy} from "../../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";
import {IPriceSource} from "../../../../contracts/interfaces/internal/oracles/IPriceSource.sol";

contract LenderStrategyTest is Test, TokensGenerator {
    BaseLenderStrategy public lenderStrategy;
    address public vault;
    IERC20Metadata public supplyAsset;
    IERC20Metadata public borrowAsset;
    uint256 public constant MAX_DEPOSIT_FEE = 100;
    IPriceSource public priceSource;

    uint256 public DEPOSIT = 1000e18;
    uint256 public BORROW = 100e18;

    function setUp() public {
        vault = makeAddr("Vault");
        supplyAsset = IERC20Metadata(BaseGetter.getBaseERC20(18));
        borrowAsset = IERC20Metadata(BaseGetter.getBaseERC20(18));
        priceSource = IPriceSource(BaseGetter.getBasePriceSource());
        lenderStrategy = new BaseLenderStrategy(
            vault,
            address(supplyAsset),
            address(borrowAsset),
            MAX_DEPOSIT_FEE,
            BaseGetter.getBaseSwapStrategy(address(priceSource)),
            vault
        );
        lenderStrategy.setPriceSource(address(priceSource));
    }

    function _deposit(uint256 amount) internal virtual {
        mintToken(address(supplyAsset), vault, amount);
        vm.startPrank(vault);
        supplyAsset.transfer(address(lenderStrategy), amount);
        lenderStrategy.deposit(amount);
        vm.stopPrank();
    }

    function test_CorrectInitialization() public virtual {
        assertEq(lenderStrategy.vault(), vault);
        assertEq(lenderStrategy.supplyAsset(), address(supplyAsset));
        assertEq(lenderStrategy.borrowAsset(), address(borrowAsset));
        assertEq(lenderStrategy.maxDepositFee(), MAX_DEPOSIT_FEE);
        assertEq(lenderStrategy.rewardsRecipient(), vault);
    }

    function test_wrongInitialization() public {
        address swapStrategy = BaseGetter.getBaseSwapStrategy(address(priceSource));

        vm.expectRevert(ILenderStrategy.LS_ZERO_ADDRESS.selector);
        new BaseLenderStrategy(
            address(0),
            address(supplyAsset),
            address(borrowAsset),
            MAX_DEPOSIT_FEE,
            swapStrategy,
            vault
        );

        vm.expectRevert(ILenderStrategy.LS_ZERO_ADDRESS.selector);
        new BaseLenderStrategy(address(vault), address(0), address(borrowAsset), MAX_DEPOSIT_FEE, swapStrategy, vault);

        vm.expectRevert(ILenderStrategy.LS_ZERO_ADDRESS.selector);
        new BaseLenderStrategy(address(vault), address(supplyAsset), address(0), MAX_DEPOSIT_FEE, swapStrategy, vault);
    }

    function test_SetMaxDepositFee() public virtual {
        assertEq(lenderStrategy.maxDepositFee(), MAX_DEPOSIT_FEE);
        lenderStrategy.setMaxDepositFee(MAX_DEPOSIT_FEE * 2);
        assertEq(lenderStrategy.maxDepositFee(), MAX_DEPOSIT_FEE * 2);
    }

    function test_ExceedDepositFee() public {
        assertEq(lenderStrategy.supplyPrincipal(), 0);
        // twice the limit
        uint256 feePerc = (MAX_DEPOSIT_FEE * 100 * 2) / DEPOSIT;
        if (feePerc == 0) {
            feePerc = 1;
        }
        lenderStrategy.setDepositFee(feePerc);
        mintToken(address(supplyAsset), vault, DEPOSIT);
        vm.startPrank(vault);
        supplyAsset.transfer(address(lenderStrategy), DEPOSIT);
        vm.expectRevert(ILenderStrategy.LS_DEPOSIT_FEE_TOO_BIG.selector);
        lenderStrategy.deposit(DEPOSIT);
        vm.stopPrank();
    }

    function test_onlyVault() public {
        _deposit(DEPOSIT);
        address someUser = makeAddr("someUser");
        vm.startPrank(someUser);

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.deposit(DEPOSIT);

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.borrow(BORROW);

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.repay(BORROW);

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.withdraw(DEPOSIT);

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.withdrawAll();

        vm.expectRevert(ILenderStrategy.LS_ONLY_VAULT.selector);
        lenderStrategy.updatePrincipal();
    }

    function test_Deposit() public {
        assertEq(lenderStrategy.supplyPrincipal(), 0);
        _deposit(DEPOSIT);
        assertEq(lenderStrategy.supplyPrincipal(), DEPOSIT, "Update state");
    }

    function test_Borrow() public {
        assertEq(lenderStrategy.borrowPrincipal(), 0);
        _deposit(DEPOSIT);

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        vm.stopPrank();

        assertEq(borrowAsset.balanceOf(vault), BORROW, "Receive tokens");
        assertEq(lenderStrategy.borrowPrincipal(), BORROW, "Update state");
    }

    function test_Repay() public {
        assertEq(lenderStrategy.borrowPrincipal(), 0);
        _deposit(DEPOSIT);
        uint256 REPAY = BORROW / 2;

        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        borrowAsset.approve(address(lenderStrategy), REPAY);
        lenderStrategy.repay(REPAY);
        vm.stopPrank();

        assertEq(borrowAsset.balanceOf(vault), BORROW - REPAY, "Pull tokens");

        assertEq(BORROW - REPAY, lenderStrategy.borrowPrincipal(), "Update state");
    }

    function test_Withdraw() public {
        assertEq(lenderStrategy.supplyPrincipal(), 0);
        _deposit(DEPOSIT);

        uint256 WITHDRAW = DEPOSIT / 2;
        uint256 balance = supplyAsset.balanceOf(vault);

        vm.startPrank(vault);
        lenderStrategy.withdraw(WITHDRAW);
        vm.stopPrank();

        assertEq(supplyAsset.balanceOf(vault), balance + WITHDRAW, "Receive tokens");

        assertEq(lenderStrategy.supplyPrincipal(), DEPOSIT - WITHDRAW, "Update state");
    }

    function test_WithdrawAll() public {
        assertEq(lenderStrategy.supplyPrincipal(), 0);
        _deposit(DEPOSIT);

        uint256 balance = supplyAsset.balanceOf(vault);

        vm.startPrank(vault);
        lenderStrategy.withdrawAll();
        vm.stopPrank();

        assertGe(supplyAsset.balanceOf(vault), balance + DEPOSIT, "Receive tokens");

        assertEq(lenderStrategy.supplyPrincipal(), 0, "Update state");
    }

    function test_hasSupplyLoss() public {
        assertEq(lenderStrategy.supplyPrincipal(), 0);
        _deposit(DEPOSIT);
        assertEq(lenderStrategy.supplyPrincipal(), DEPOSIT);
        assertEq(lenderStrategy.supplyBalance(), DEPOSIT);
        assertEq(lenderStrategy.hasSupplyLoss(), false);
        lenderStrategy.setSupplyLoss(50, 0, 0);
        assertEq(lenderStrategy.supplyBalance(), DEPOSIT / 2);
        assertEq(lenderStrategy.hasSupplyLoss(), true);
    }

    function test_preSupplyLossSnapshot() public {
        _deposit(DEPOSIT);
        vm.startPrank(vault);
        lenderStrategy.borrow(BORROW);
        lenderStrategy.setSupplyLoss(50, 50, 10);
        (uint256 supplyLoss, uint256 borrowLoss, uint256 fee) = lenderStrategy.preSupplyLossSnapshot();
        vm.stopPrank();
        assertEq(supplyLoss, DEPOSIT / 2, "Supply loss");
        assertEq(borrowLoss, BORROW / 2, "Borrow loss");
        assertEq(fee, DEPOSIT / 10, "Fee");
    }

    function test_recogniseRewardsInBase() public {
        assertEq(lenderStrategy.rewardsRecipient(), vault);
        uint256 before = borrowAsset.balanceOf(vault);
        lenderStrategy.recogniseRewardsInBase();
        uint256 rewards = borrowAsset.balanceOf(vault) - before;
        assertEq(rewards, 100 * (10 ** borrowAsset.decimals()), "Receive rewards");
    }
}
