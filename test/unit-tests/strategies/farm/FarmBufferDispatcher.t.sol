pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import "../../../../contracts/strategies/farming/FarmBufferDispatcher.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import {BaseFarmStrategy} from "../../../base/BaseFarmStrategy.sol";

contract FarmBufferDispatcherTest is Test {
    FarmBufferDispatcher public dispatcher;
    address public vaultAddress;
    address public workingAsset;
    uint256 public constant BUFFER = 1e18;

    function setUp() public {
        dispatcher = new FarmBufferDispatcher();
        vaultAddress = vm.addr(1);
        workingAsset = BaseGetter.getBaseERC20(18);

        dispatcher.initialize(vaultAddress, workingAsset, address(this));
        dispatcher.grantRole(Roles.ALPHA, address(this));
        dispatcher.grantRole(Roles.BETA, address(this));
        dispatcher.grantRole(Roles.GAMMA, address(this));
        dispatcher.grantRole(Roles.GAMMA, vaultAddress);
    }

    function test_CorrectInitialization() public view {
        assertTrue(address(dispatcher.farmBuffer()) != address(0));
    }

    function test_IncreaseBufferSize() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
    }

    function test_IncreasesBufferSizeUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        dispatcher.increaseBufferSize(BUFFER);
    }

    function test_DecreaseBufferSize() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);
        dispatcher.decreaseBufferSize(BUFFER);

        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), 0);
    }

    function test_DecreasesBufferSizeUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        dispatcher.decreaseBufferSize(BUFFER);
    }

    function test_FillBufferOnDeposit() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);

        dispatcher.dispatch();
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), BUFFER * 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER / 2);
        assertEq(dispatcher.balance(), BUFFER * 2 - BUFFER / 2);
        IToken(workingAsset).mint(address(dispatcher), BUFFER / 2);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), BUFFER * 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(dispatcher.balance(), BUFFER * 2);
    }

    function test_DepositInFarmStrategy() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER);

        dispatcher.dispatch();
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(dispatcher.balance(), BUFFER);
    }

    function test_FulfillBufferAndDeposit() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, BUFFER * 3, address(0));
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);

        dispatcher.dispatch();
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);
        IToken(workingAsset).mint(address(dispatcher), BUFFER);

        vm.prank(vaultAddress);
        dispatcher.dispatch();
        (, , uint256 totalDeposit, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit, BUFFER * 2 + BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), BUFFER * 2 + BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(dispatcher.balance(), BUFFER * 2 + BUFFER / 2);
    }

    function test_WithdrawFromBuffer() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);

        dispatcher.dispatch();
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);

        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER / 2);
        assertEq(dispatcher.balance(), BUFFER * 2 - BUFFER / 2);
    }

    function test_WithdrawWhenBufferIsNotEnough() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);
        dispatcher.dispatch();

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);
        vm.prank(vaultAddress);

        // Withdraw all
        dispatcher.withdraw(BUFFER * 2 - BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER * 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(dispatcher.balance(), 0);
    }

    function test_FillBufferFirstWhenFarmLoss() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, BUFFER * 2, address(0));
        IToken(workingAsset).mint(address(this), BUFFER);
        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);
        dispatcher.dispatch();

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);
        // Simulate farm loss
        vm.prank(address(dispatcher));
        IFarmStrategy(newStrategy1).withdraw(BUFFER);
        // Transfer the loss to not be accounted in the balance
        vm.prank(address(dispatcher));
        IToken(workingAsset).transfer(vaultAddress, BUFFER);
        assertEq(dispatcher.balance(), BUFFER / 2);

        // This should fill the buffer and withdraws 0.5
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER * 2);

        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER * 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(dispatcher.balance(), 0);
    }

    function test_WithdrawBufferToNotBeLocked() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, BUFFER * 2, address(0));
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);
        dispatcher.dispatch();

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);

        dispatcher.decreaseBufferCapacity();

        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), 0);
        assertEq(dispatcher.balance(), BUFFER * 2 - BUFFER / 2);
    }

    function test_BalanceCalculation() public {
        // 1. initially -> 10 buffer
        // 2. deposit 15 -> add 15 directly in the farming (15 in the farm, 10 in the buffer)
        // 3. withdraw 10 -> take out from the buffer (15 in the farm, 0 in the buffer)
        // 4. deposit 5 -> add 5 directly in the farming (fulfill the buffer) (10 in the farm, 10 in the buffer)
        // 5. withdraw 5 -> take out from the farm (5 in the farm, 10 in the buffer)
        // 6. withdraw 5 -> take out from the farm (0 in the farm, 10 in the buffer)
        uint256 fifteen = 15e17;
        uint256 ten = 1e18;
        uint256 five = 5e17;
        // 1.
        IToken(workingAsset).mint(address(this), BUFFER);
        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        // 2.
        IToken(workingAsset).mint(address(dispatcher), fifteen);
        dispatcher.dispatch();

        // 3.
        vm.prank(vaultAddress);
        dispatcher.withdraw(ten);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), ten);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), fifteen);

        // 4.
        vm.prank(vaultAddress);
        IToken(workingAsset).transfer(address(dispatcher), five);
        dispatcher.dispatch();
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), ten);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), ten);

        // 5.
        vm.prank(vaultAddress);
        dispatcher.withdraw(five);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), ten);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), ten);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), five);

        // 6.
        vm.prank(vaultAddress);
        dispatcher.withdraw(five);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), fifteen);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), ten);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
    }

    function test_LossNotCoveredByTheBuffer() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, BUFFER * 2, address(0));
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 3);
        dispatcher.dispatch();

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER);

        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), 0);
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER * 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        // Simulate farm loss
        vm.prank(address(dispatcher));
        IFarmStrategy(newStrategy1).withdraw(BUFFER / 2);
        // Transfer the loss to not be accounted in the balance
        vm.prank(address(dispatcher));
        IToken(workingAsset).transfer(address(this), BUFFER / 2);
        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER * 3 - BUFFER / 2);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher.farmBuffer())), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER / 2);
    }

    function test_BufferCapacityHigherThanBalance() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER);

        vm.prank(address(dispatcher));
        IToken(workingAsset).transfer(address(this), BUFFER / 2);

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER / 2);

        assertEq(dispatcher.balance(), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), BUFFER / 2);
        assertEq(dispatcher.farmBuffer().capacityMissing(), 0);
    }

    function test_BufferToRefillHigherThanBalance() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        IToken(workingAsset).mint(address(dispatcher), BUFFER * 2);

        vm.prank(vaultAddress);
        dispatcher.withdraw(BUFFER);

        // Simulate farm loss
        IToken(workingAsset).burn(address(dispatcher), BUFFER * 2);

        assertEq(dispatcher.balance(), 0);
    }

    function test_ApprovalResetAfterFill() public {
        IToken(workingAsset).mint(address(this), BUFFER);

        // Increase buffer size
        IToken(workingAsset).approve(address(dispatcher), BUFFER);
        dispatcher.increaseBufferSize(BUFFER);

        // Mint tokens to dispatcher and fill buffer
        IToken(workingAsset).mint(address(dispatcher), BUFFER);
        dispatcher.dispatch();

        // Verify approval was reset
        assertEq(IToken(workingAsset).allowance(address(dispatcher), address(dispatcher.farmBuffer())), 0);
    }
}
