pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../utils/VaultTestSuite.sol";
import "../../contracts/common/Roles.sol";
import "../../contracts/interfaces/internal/access/IIngress.sol";
import {BorrowVerifierSigUtils} from "../utils/BorrowVerifierSigUtils.sol";

contract IngressTest is VaultTestSuite {
    IIngress public ingress;
    IERC20 public supplyUnderlying;
    IERC20 public borrowUnderlying;

    address aliceUser = makeAddr("aliceUser");
    address bobUser = makeAddr("bobUser");
    address alphaUser = makeAddr("alphaUser");
    address betaUser = makeAddr("betaUser");
    address gammaUser = makeAddr("gammaUser");
    address adminUser;

    function setUp() public override {
        super.setUp();

        supplyUnderlying = IERC20(vault.supplyUnderlying());
        borrowUnderlying = IERC20(vault.borrowUnderlying());

        ingress = IIngress(vault.ingressControl());

        adminUser = deployer.GRAND_ADMIN();
        vm.startPrank(adminUser);
        ingress.grantRole(Roles.ALPHA, alphaUser);
        ingress.grantRole(Roles.BETA, betaUser);
        ingress.grantRole(Roles.GAMMA, gammaUser);
        vm.stopPrank();

        vm.clearMockedCalls();
    }

    function _sanction(address user, bool toSanction) internal {
        address[] memory list = new address[](1);
        list[0] = user;
        vm.prank(gammaUser);
        ingress.setSanctioned(list, toSanction);
    }

    function _disable(bytes4 selector, bool disabled) internal {
        bytes4[] memory newFunctions = new bytes4[](1);
        newFunctions[0] = selector;
        vm.prank(gammaUser);
        ingress.setFunctionsPause(newFunctions, disabled);
    }

    function test_validateDeposit() public {
        mintToken(vault.supplyUnderlying(), aliceUser, 20_000);
        vm.prank(aliceUser);
        supplyUnderlying.approve(address(vault), type(uint256).max);
        vm.prank(adminUser);
        ingress.setDepositLimits(100, 1_000, 1_500);
        uint256 TOO_LITTLE = 10;
        uint256 TOO_MUCH = 2_000;
        uint256 OK_DEPOSIT = 500;

        vm.startPrank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_USER_DEPOSIT_MINIMUM_UNMET.selector);
        vault.deposit(TOO_LITTLE, aliceUser);

        vm.expectRevert(IIngress.IN_V1_USER_DEPOSIT_LIMIT_EXCEEDED.selector);
        vault.deposit(TOO_MUCH, aliceUser);
        vm.stopPrank();

        vm.prank(gammaUser);
        ingress.setProtocolPause(true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_PROTOCOL_PAUSED.selector);
        vault.deposit(OK_DEPOSIT, aliceUser);
        vm.prank(gammaUser);
        ingress.setProtocolPause(false);

        _disable(IIngress.validateDeposit.selector, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vault.deposit(OK_DEPOSIT, aliceUser);
        _disable(IIngress.validateDeposit.selector, false);

        _sanction(aliceUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.deposit(OK_DEPOSIT, aliceUser);
        _sanction(aliceUser, false);

        // sanctioned onBehalf
        address[] memory allowee = new address[](1);
        allowee[0] = aliceUser;
        vm.prank(bobUser);
        vault.allowOnBehalf(allowee, true);
        _sanction(bobUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.deposit(OK_DEPOSIT, bobUser);
        _sanction(bobUser, false);

        // deposit 500
        vm.prank(aliceUser);
        vault.deposit(OK_DEPOSIT, aliceUser);

        // deposit 1000
        mintToken(vault.supplyUnderlying(), bobUser, 20_000);
        vm.startPrank(bobUser);
        supplyUnderlying.approve(address(vault), type(uint256).max);
        vault.deposit(OK_DEPOSIT * 2, bobUser);
        vm.stopPrank();

        // deposit 500
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_VAULT_DEPOSIT_LIMIT_EXCEEDED.selector);
        vault.deposit(OK_DEPOSIT, aliceUser);
        vm.stopPrank();
    }

    function test_validateRepay() public {
        depositAndBorrow(aliceUser);
        mintToken(address(borrowUnderlying), aliceUser, REPAY);
        mintToken(address(borrowUnderlying), bobUser, REPAY);

        _disable(IIngress.validateRepay.selector, true);
        vm.startPrank(aliceUser);
        address[] memory allowee = new address[](1);
        allowee[0] = bobUser;
        vault.allowOnBehalf(allowee, true);
        borrowUnderlying.approve(address(vault), REPAY);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vault.repay(REPAY, aliceUser);
        vm.stopPrank();
        _disable(IIngress.validateRepay.selector, false);

        _sanction(bobUser, true);
        vm.startPrank(bobUser);
        borrowUnderlying.approve(address(vault), REPAY);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.repay(REPAY, aliceUser);
        vm.stopPrank();
        _sanction(bobUser, false);

        vm.prank(bobUser);
        vault.repay(REPAY, aliceUser);
    }

    function test_validateTransfer() public {
        uint256 TRANSFER = DEPOSIT / 2;
        IERC20 supplyToken = IERC20(address(vault.supplyToken()));
        deposit(aliceUser);

        address[] memory allowee = new address[](1);
        allowee[0] = aliceUser;
        vm.prank(bobUser);
        vault.allowOnBehalf(allowee, true);

        _disable(IIngress.validateTransfer.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(aliceUser);
        supplyToken.transfer(bobUser, TRANSFER);
        _disable(IIngress.validateTransfer.selector, false);

        vm.prank(gammaUser);
        ingress.setProtocolPause(true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_PROTOCOL_PAUSED.selector);
        supplyToken.transfer(bobUser, TRANSFER);
        vm.prank(gammaUser);
        ingress.setProtocolPause(false);

        _sanction(bobUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        supplyToken.transfer(bobUser, TRANSFER);
        _sanction(bobUser, false);

        _sanction(aliceUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        supplyToken.transfer(bobUser, TRANSFER);
        _sanction(aliceUser, false);

        vm.prank(aliceUser);
        supplyToken.transfer(bobUser, TRANSFER);
    }

    function test_validateCommit() public {
        deposit(aliceUser);
        vault.rebalance();
        harvestWithRewards();

        _disable(IIngress.validateCommit.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vault.updatePosition(aliceUser);
        _disable(IIngress.validateCommit.selector, false);
    }

    function test_validateRebalance() public {
        deposit(aliceUser);
        vm.prank(bobUser);
        vm.expectRevert();
        vault.rebalance();

        vm.prank(gammaUser);
        vault.rebalance();

        _disable(IIngress.validateRebalance.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(gammaUser);
        vault.rebalance();
        _disable(IIngress.validateRebalance.selector, false);

        vm.prank(gammaUser);
        vault.rebalance();
    }

    function test_validateSnapshotSupplyLoss() public {
        vm.expectRevert();
        vm.prank(alphaUser);
        vault.snapshotSupplyLoss();

        vm.expectRevert();
        vm.prank(betaUser);
        vault.snapshotSupplyLoss();

        vm.prank(gammaUser);
        vault.snapshotSupplyLoss();
    }

    function test_validateLiquidateUsers() public {
        deposit(aliceUser);

        address[] memory list = new address[](1);
        list[0] = aliceUser;
        vm.prank(bobUser);
        vault.liquidateUsers(list, 0);

        _disable(IIngress.validateLiquidateUsers.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(bobUser);
        vault.liquidateUsers(list, 0);
        _disable(IIngress.validateLiquidateUsers.selector, false);

        _sanction(bobUser, true);
        vm.prank(bobUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.liquidateUsers(list, 0);
        _sanction(bobUser, false);
    }

    function test_validateWithdraw() public {
        deposit(aliceUser);

        vm.prank(aliceUser);
        vault.withdraw(DEPOSIT / 5, aliceUser);

        vm.prank(gammaUser);
        ingress.setProtocolPause(true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_PROTOCOL_PAUSED.selector);
        vault.withdraw(DEPOSIT / 5, aliceUser);
        vm.prank(gammaUser);
        ingress.setProtocolPause(false);

        _disable(IIngress.validateWithdraw.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(aliceUser);
        vault.withdraw(DEPOSIT / 5, aliceUser);
        _disable(IIngress.validateWithdraw.selector, false);

        _sanction(aliceUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.withdraw(DEPOSIT / 5, aliceUser);
        _sanction(aliceUser, false);

        _sanction(bobUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.withdraw(DEPOSIT / 5, bobUser);
        _sanction(bobUser, false);
    }

    function test_validateBorrow() public {
        deposit(aliceUser);
        deposit(aliceUser);

        vm.prank(aliceUser);
        vault.borrow(BORROW);

        vm.prank(gammaUser);
        ingress.setProtocolPause(true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_PROTOCOL_PAUSED.selector);
        vault.borrow(BORROW);
        vm.prank(gammaUser);
        ingress.setProtocolPause(false);

        _disable(IIngress.validateBorrow.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(aliceUser);
        vault.borrow(BORROW);
        _disable(IIngress.validateBorrow.selector, false);

        _sanction(aliceUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.borrow(BORROW);
        _sanction(aliceUser, false);

        (address beneficient, address executor, bytes memory signature) = BorrowVerifierSigUtils.approveBorrow(
            vm,
            address(vault.borrowVerifier()),
            BORROW
        );
        deposit(beneficient);

        _sanction(beneficient, true);
        vm.prank(executor);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.borrowOnBehalfOf(BORROW, beneficient, 1 days, signature);
        _sanction(beneficient, false);

        vm.prank(executor);
        vault.borrowOnBehalfOf(BORROW, beneficient, 1 days, signature);

        vm.prank(aliceUser);
        vault.borrow(BORROW);
    }

    function test_validateClaimRewards() public {
        deposit(aliceUser);
        harvestWithRewards();
        vm.prank(aliceUser);
        vault.claimRewards(type(uint256).max);

        harvestWithRewards();

        vm.prank(gammaUser);
        ingress.setProtocolPause(true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_PROTOCOL_PAUSED.selector);
        vault.claimRewards(type(uint256).max);
        vm.prank(gammaUser);
        ingress.setProtocolPause(false);

        _disable(IIngress.validateClaimRewards.selector, true);
        vm.expectRevert(IIngress.IN_V1_FUNCTION_PAUSED.selector);
        vm.prank(aliceUser);
        vault.claimRewards(type(uint256).max);
        _disable(IIngress.validateClaimRewards.selector, false);

        _sanction(aliceUser, true);
        vm.prank(aliceUser);
        vm.expectRevert(IIngress.IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED.selector);
        vault.claimRewards(type(uint256).max);
        _sanction(aliceUser, false);

        vm.prank(aliceUser);
        vault.claimRewards(type(uint256).max);
    }

    function test_rateLimitWithdraw() public {
        uint256[3] memory newPeriod = [uint256(10), 10, 10];
        uint256[3] memory newAmount = [DEPOSIT * 2, BORROW * 2, REWARDS * 2];
        vm.prank(betaUser);
        ingress.setRateLimit(newPeriod, newAmount);

        deposit(aliceUser, DEPOSIT * 10);
        vm.startPrank(aliceUser);
        vault.withdraw(DEPOSIT, aliceUser);
        vm.roll(block.number + 3);
        vault.withdraw(DEPOSIT, aliceUser);
        vm.expectRevert(IIngress.IN_V1_WITHDRAW_RATE_LIMIT.selector);
        vault.withdraw(DEPOSIT, aliceUser);
        vm.roll(block.number + 2);
        vault.withdraw(DEPOSIT, aliceUser);
        vm.roll(block.number + 10);
        vault.withdraw(DEPOSIT * 2, aliceUser);
        vm.roll(block.number + 1);
        vm.expectRevert(IIngress.IN_V1_WITHDRAW_RATE_LIMIT.selector);
        vault.withdraw((DEPOSIT * 2) / 9, aliceUser);
        vault.withdraw((DEPOSIT * 2) / 10, aliceUser);
        vm.stopPrank();
    }

    function test_rateLimitBorrow() public {
        uint256[3] memory newPeriod = [uint256(10), 10, 10];
        uint256[3] memory newAmount = [DEPOSIT * 2, BORROW * 2, REWARDS * 2];
        vm.prank(betaUser);
        ingress.setRateLimit(newPeriod, newAmount);

        deposit(aliceUser, DEPOSIT * 10);
        vm.startPrank(aliceUser);
        vault.borrow(BORROW);
        vm.roll(block.number + 3);
        vault.borrow(BORROW);
        vm.expectRevert(IIngress.IN_V1_BORROW_RATE_LIMIT.selector);
        vault.borrow(BORROW);
        vm.roll(block.number + 2);
        vault.borrow(BORROW);
        vm.roll(block.number + 10);
        vault.borrow(BORROW * 2);
        vm.roll(block.number + 1);
        vm.expectRevert(IIngress.IN_V1_BORROW_RATE_LIMIT.selector);
        vault.borrow((BORROW * 2) / 9);
        vault.borrow((BORROW * 2) / 10);
        vm.stopPrank();
    }

    function test_rateLimitClaimRewards() public {
        uint256[3] memory newPeriod = [uint256(10), 10, 10];
        uint256[3] memory newAmount = [DEPOSIT * 2, BORROW * 2, REWARDS * 2];
        vm.prank(betaUser);
        ingress.setRateLimit(newPeriod, newAmount);

        deposit(aliceUser, DEPOSIT * 10);
        vm.roll(block.number + 1);
        harvestWithRewards(REWARDS * 10);
        disableReserveFactor();

        vm.startPrank(aliceUser);
        vault.claimRewards(REWARDS);
        vm.roll(block.number + 3);
        vault.claimRewards(REWARDS);
        vm.expectRevert(IIngress.IN_V1_CLAIM_RATE_LIMIT.selector);
        vault.claimRewards(REWARDS);
        vm.roll(block.number + 2);
        vault.claimRewards(REWARDS);
        vm.roll(block.number + 10);
        vault.claimRewards(REWARDS * 2);
        vm.roll(block.number + 1);
        vm.expectRevert(IIngress.IN_V1_CLAIM_RATE_LIMIT.selector);
        vault.claimRewards((REWARDS * 2) / 9);
        vault.claimRewards((REWARDS * 2) / 10);
        vm.stopPrank();
    }
}
