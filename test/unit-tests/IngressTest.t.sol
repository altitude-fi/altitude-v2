pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Ingress} from "../../contracts/access/Ingress.sol";
import "../../contracts/interfaces/internal/access/IIngress.sol";
import "../../contracts/common/Roles.sol";

contract IngressTest is Test {
    Ingress ingress;

    address someUser = makeAddr("someUser");
    address alphaUser = makeAddr("alphaUser");
    address betaUser = makeAddr("betaUser");
    address gammaUser = makeAddr("gammaUser");
    address adminUser = makeAddr("adminUser");

    address[] sanctioned; // initial sanctioned list of addresses
    uint256 userMinDepositLimit; // initial user min deposit limit
    uint256 userMaxDepositLimit; // initial user max deposit limit
    uint256 vaultDepositLimit; // initial vault deposit limit
    uint256[3] rateLimitPeriod; // initial rate limit period
    uint256[3] rateLimitAmount; // initial rate limit amount

    function setUp() public {
        sanctioned = [makeAddr("sanctioned1"), makeAddr("sanctioned2")];
        userMinDepositLimit = 100;
        userMaxDepositLimit = 1000;
        vaultDepositLimit = 10000;
        rateLimitPeriod = [1, 2, 3];
        rateLimitAmount = [10, 20, 30];

        ingress = new Ingress(
            adminUser,
            sanctioned,
            userMinDepositLimit,
            userMaxDepositLimit,
            vaultDepositLimit,
            rateLimitPeriod,
            rateLimitAmount
        );

        vm.startPrank(adminUser);
        ingress.grantRole(Roles.ALPHA, alphaUser);
        ingress.grantRole(Roles.BETA, betaUser);
        ingress.grantRole(Roles.GAMMA, gammaUser);
        vm.stopPrank();
    }

    function test_CorrectInitialization() public view {
        assertEq(ingress.hasRole(ingress.DEFAULT_ADMIN_ROLE(), adminUser), true);
        for (uint256 i = 0; i < sanctioned.length; i++) {
            assertEq(ingress.sanctioned(sanctioned[i]), true);
        }
        assertEq(ingress.userMinDepositLimit(), userMinDepositLimit);
        assertEq(ingress.userMaxDepositLimit(), userMaxDepositLimit);
        assertEq(ingress.vaultDepositLimit(), vaultDepositLimit);
        for (uint256 i = 0; i < 3; i++) {
            (
                uint256 period, // Time period in blocks until the rate limit resets
                uint256 amount, // Amount allowed to be transferred in the period
                uint256 available, // Amount available to be transferred in the period
                uint256 updated
            ) = ingress.rateLimit(i);

            assertEq(period, rateLimitPeriod[i]);
            assertEq(amount, rateLimitAmount[i]);
            assertEq(available, rateLimitAmount[i]);
            assertEq(updated, 0);
        }
    }

    function test_setRateLimit() public {
        uint256[3] memory newPeriod = [uint256(10), 20, 30];
        uint256[3] memory newAmount = [uint256(100), 200, 300];

        vm.prank(someUser);
        vm.expectRevert();
        ingress.setRateLimit(newPeriod, newAmount);

        vm.startPrank(betaUser);
        ingress.setRateLimit(newPeriod, newAmount);
        for (uint256 i = 0; i < 3; i++) {
            (
                uint256 period, // Time period in blocks until the rate limit resets
                uint256 amount, // Amount allowed to be transferred in the period
                uint256 available, // Amount available to be transferred in the period

            ) = ingress.rateLimit(i);

            assertEq(period, newPeriod[i]);
            assertEq(amount, newAmount[i]);
            assertEq(available, newAmount[i]);
        }
    }

    function test_setSanctioned() public {
        address[] memory newSanctioned = new address[](2);
        newSanctioned[0] = makeAddr("sanctioned1");
        newSanctioned[1] = makeAddr("sanctioned2");

        vm.prank(someUser);
        vm.expectRevert();
        ingress.setSanctioned(newSanctioned, true);

        vm.startPrank(gammaUser);
        ingress.setSanctioned(newSanctioned, true);

        for (uint256 i = 0; i < newSanctioned.length; i++) {
            assertEq(ingress.sanctioned(newSanctioned[i]), true);
        }
        address[] memory delSanctioned = new address[](1);
        delSanctioned[0] = newSanctioned[1];
        ingress.setSanctioned(delSanctioned, false);
        assertEq(ingress.sanctioned(newSanctioned[0]), true);
        assertEq(ingress.sanctioned(newSanctioned[1]), false);
    }

    function test_setDepositLimits() public {
        uint256 _userMinDepositLimit = ingress.userMinDepositLimit() + 1;
        uint256 _userMaxDepositLimit = ingress.userMaxDepositLimit() + 1;
        uint256 _vaultDepositLimit = ingress.vaultDepositLimit() + 1;

        vm.prank(someUser);
        vm.expectRevert();
        ingress.setDepositLimits(_userMinDepositLimit, _userMaxDepositLimit, _vaultDepositLimit);

        vm.startPrank(betaUser);
        ingress.setDepositLimits(_userMinDepositLimit, _userMaxDepositLimit, _vaultDepositLimit);

        assertEq(ingress.userMinDepositLimit(), _userMinDepositLimit);
        assertEq(ingress.userMaxDepositLimit(), _userMaxDepositLimit);
        assertEq(ingress.vaultDepositLimit(), _vaultDepositLimit);
    }

    function test_setProtocolPause() public {
        bool _pause = !ingress.pause();

        vm.prank(someUser);
        vm.expectRevert();
        ingress.setProtocolPause(_pause);

        vm.startPrank(gammaUser);
        ingress.setProtocolPause(_pause);

        assertEq(ingress.pause(), _pause);
    }

    function test_setFunctionsPause() public {
        bytes4[] memory newFunctions = new bytes4[](2);
        newFunctions[0] = 0x12345678;
        newFunctions[1] = 0x1234567f;

        for (uint256 i = 0; i < newFunctions.length; i++) {
            assertEq(ingress.isFunctionDisabled(newFunctions[i]), false);
        }

        vm.prank(someUser);
        vm.expectRevert();
        ingress.setFunctionsPause(newFunctions, true);

        vm.startPrank(gammaUser);
        ingress.setFunctionsPause(newFunctions, true);

        for (uint256 i = 0; i < newFunctions.length; i++) {
            assertEq(ingress.isFunctionDisabled(newFunctions[i]), true);
        }
        bytes4[] memory delFunctions = new bytes4[](1);
        delFunctions[0] = newFunctions[1];
        ingress.setFunctionsPause(delFunctions, false);
        assertEq(ingress.isFunctionDisabled(newFunctions[0]), true);
        assertEq(ingress.isFunctionDisabled(newFunctions[1]), false);
    }

    function test_rateLimitPermissions() public {
        vm.startPrank(someUser);
        vm.expectRevert();
        ingress.validateWithdraw(address(1), address(1), 1);
        vm.expectRevert();
        ingress.validateBorrow(address(1), address(1), 1);
        vm.expectRevert();
        ingress.validateClaimRewards(address(1), 1);
        vm.stopPrank();

        vm.startPrank(gammaUser);
        ingress.validateWithdraw(address(1), address(1), 1);
        ingress.validateBorrow(address(1), address(1), 1);
        ingress.validateClaimRewards(address(1), 1);
        vm.stopPrank();
    }
}
