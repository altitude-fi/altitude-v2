// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseGetter} from "../../../base/BaseGetter.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";
import {ForkTest} from "../../../ForkTest.sol";
import {IFarmStrategy} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmStrategy.sol";

abstract contract FarmStrategyIntegrationTest is ForkTest, TokensGenerator {
    IFarmStrategy public farmStrategy;

    address public dispatcher;
    IERC20Metadata public asset;
    IERC20Metadata public farmAsset;

    uint256 public FEE_TOLERANCE;
    uint256 public constant MAX_FEE_TOLERANCE = 1e18;

    uint256 public DEPOSIT;

    function setUp() public override {
        super.setUp();

        _setUp();

        // Preload amount to the dispatcher to be able to deposit it in each test
        _mintAsset(dispatcher, DEPOSIT);
    }

    function test_CorrectInitialization() public view virtual {
        assertEq(farmStrategy.farmAsset(), address(farmAsset));
        assertEq(farmStrategy.farmDispatcher(), dispatcher);
        assertEq(farmStrategy.rewardsRecipient(), dispatcher);
        assertEq(farmStrategy.asset(), address(asset));
    }

    function test_Deposit() public virtual {
        uint256 balanceBefore = farmStrategy.balance();

        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        uint256 balanceAfter = farmStrategy.balance();

        assertTrue(balanceAfter > balanceBefore);
        assertTrue(balanceBefore == 0);

        uint256 depositTolerance = DEPOSIT - (DEPOSIT * FEE_TOLERANCE) / MAX_FEE_TOLERANCE;
        assertTrue(balanceAfter >= depositTolerance);
    }

    function test_WithdrawHalfDeposit() public virtual {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        uint256 amountWithdrawn = asset.balanceOf(dispatcher);

        farmStrategy.withdraw(DEPOSIT / 2);
        amountWithdrawn = asset.balanceOf(dispatcher) - amountWithdrawn;
        vm.stopPrank();
        // Withdrawal from curve may return slightly more
        assertGe(amountWithdrawn, DEPOSIT / 2);
        uint256 remainingTolerance = (DEPOSIT / 2) - ((DEPOSIT / 2) * FEE_TOLERANCE) / MAX_FEE_TOLERANCE;

        assertGe(farmStrategy.balance(), remainingTolerance);
    }

    function test_WithdrawAll() public virtual {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);

        uint256 amountWithdrawn = asset.balanceOf(dispatcher);
        uint256 farmBalance = farmStrategy.balance();
        farmStrategy.withdraw(type(uint256).max);
        amountWithdrawn = asset.balanceOf(dispatcher) - amountWithdrawn;

        vm.stopPrank();
        if (farmStrategy.balance() > 0) {
            // $1 for $10M
            assertApproxEqRel(farmBalance, amountWithdrawn, 0.0000001e18, "More than 0.00001% dust");
        }

        uint256 withdrawnTolerance = DEPOSIT - (DEPOSIT * FEE_TOLERANCE) / MAX_FEE_TOLERANCE;

        assertGe(amountWithdrawn, withdrawnTolerance, "Fee tolerance");
    }

    function test_RewardsRecognition() public virtual {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        uint256 balanceBefore = farmStrategy.balance();
        _accumulateRewards();
        uint256 rewards = farmStrategy.recogniseRewardsInBase();

        uint256 balanceAfter = farmStrategy.balance();

        assertTrue(balanceBefore == balanceAfter);
        assertTrue(asset.balanceOf(dispatcher) == rewards);
    }

    function test_FarmBalance() public virtual {
        uint256 initialBalance = asset.balanceOf(dispatcher);
        uint256 five = 5 * 10 ** asset.decimals();
        uint256 ten = 10 * 10 ** asset.decimals();
        uint256 fifteen = 15 * 10 ** asset.decimals();

        _mintAsset(dispatcher, fifteen);

        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), fifteen);
        farmStrategy.deposit(fifteen);
        farmStrategy.withdraw(ten);

        asset.approve(address(farmStrategy), five);
        farmStrategy.deposit(five);
        farmStrategy.withdraw(five);
        vm.stopPrank();

        // Withdrawal from farm strategy may return slightly more (for example curve)

        assertGe(asset.balanceOf(dispatcher) - initialBalance, ten);

        // TODO this tolerance check is incorrect
        // 100
        // w 50 1% fee = 0.5
        // 49.5 is ok

        // 49.5 + 50 = 99.5
        // w 50 1% fee = 0.5
        // 49.5 - 0.495 = 49.005 is ok
        // but it is 99.5 - 50 - 0.5 = 49

        uint256 balanceTolerance = five - (five * FEE_TOLERANCE) / MAX_FEE_TOLERANCE;

        assertGe(farmStrategy.balance(), balanceTolerance, "Fee tolerance");
    }

    function test_EmergencyWithdraw() public {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        assertEq(farmAsset.balanceOf(address(farmStrategy)), 0);
        farmStrategy.emergencyWithdraw();

        assertGt(farmAsset.balanceOf(address(farmStrategy)), 0);
    }

    function test_EmergencySwap() public {
        uint256 initialBalance = asset.balanceOf(dispatcher);
        farmStrategy.emergencyWithdraw();

        address[] memory rewards = _accumulateRewards();

        farmStrategy.emergencySwap(rewards);

        assertGt(asset.balanceOf(dispatcher), initialBalance);
    }

    function _mintAsset(address to, uint256 amount) internal virtual {
        mintToken(Constants.USDC, to, amount);
    }

    function _setUp() internal virtual;

    function _accumulateRewards() internal virtual returns (address[] memory);
}
