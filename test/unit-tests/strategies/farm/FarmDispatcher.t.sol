pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import "../../../../contracts/strategies/farming/FarmDispatcher.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import {BaseFarmStrategy} from "../../../base/BaseFarmStrategy.sol";

contract FarmDispatcherTest is Test {
    FarmDispatcher public dispatcher;
    address public vaultAddress;
    address public workingAsset;
    uint256 public constant CAP = 1e18;

    function setUp() public {
        dispatcher = new FarmDispatcher();
        vaultAddress = vm.addr(1);
        workingAsset = BaseGetter.getBaseERC20(18);

        dispatcher.initialize(vaultAddress, workingAsset, address(this));
        dispatcher.grantRole(Roles.ALPHA, address(this));
        dispatcher.grantRole(Roles.BETA, address(this));
        dispatcher.grantRole(Roles.GAMMA, address(this));
        dispatcher.grantRole(Roles.GAMMA, vaultAddress);
    }

    /**
     * @dev Creates a new BaseFarmStrategy with standard test parameters
     * @return BaseFarmStrategy A new strategy instance
     */
    function createStrategyHelper() internal returns (BaseFarmStrategy) {
        return new BaseFarmStrategy(workingAsset, address(dispatcher), address(0), address(0));
    }

    function test_CorrectInitialization() public view {
        assertEq(dispatcher.vault(), vaultAddress);
        assertEq(dispatcher.asset(), workingAsset);
        assertEq(dispatcher.hasRole(dispatcher.DEFAULT_ADMIN_ROLE(), address(this)), true);
        (bool active, , , address prev, address next) = dispatcher.strategies(address(0));
        assertEq(prev, address(0));
        assertEq(next, address(0));
        assertEq(active, true);
    }

    function test_AddStrategy() public {
        address newStrategy = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy, CAP, address(0));
        (, , , address firstPrev, address firstNext) = dispatcher.strategies(address(0));
        (bool secondActive, uint256 secondAmount, , address secondPrev, address secondNext) = dispatcher.strategies(
            newStrategy
        );
        assertEq(firstPrev, newStrategy);
        assertEq(firstNext, newStrategy);
        assertEq(secondActive, true);
        assertEq(secondAmount, CAP);
        assertEq(secondPrev, address(0));
        assertEq(secondNext, address(0));
    }

    function test_AddStrategyWithIncorrectDispatcher() public {
        FarmDispatcher newDispatcher = new FarmDispatcher();
        newDispatcher.initialize(vaultAddress, workingAsset, address(this));
        newDispatcher.grantRole(Roles.ALPHA, address(this));
        newDispatcher.grantRole(Roles.BETA, address(this));
        newDispatcher.grantRole(Roles.GAMMA, address(this));
        newDispatcher.grantRole(Roles.GAMMA, vaultAddress);

        BaseFarmStrategy newStrategyWithWrongDispatcher = new BaseFarmStrategy(
            workingAsset,
            address(newDispatcher), // Wrong dispatcher
            address(0),
            address(0)
        );

        vm.expectRevert(IFarmDispatcher.FD_INVALID_STRATEGY_DISPATCHER.selector);
        dispatcher.addStrategy(address(newStrategyWithWrongDispatcher), CAP, address(0));
    }

    function test_AddStrategyAtPosition() public {
        address newStrategy1 = address(createStrategyHelper());
        address newStrategy2 = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, address(0));

        (, , , address initialPrev, address initialNext) = dispatcher.strategies(address(0));
        (, , , address newStrategy1Prev, address newStrategy1Next) = dispatcher.strategies(newStrategy1);
        (, , , address newStrategy2Prev, address newStrategy2Next) = dispatcher.strategies(newStrategy2);
        assertEq(initialPrev, newStrategy1);
        assertEq(initialNext, newStrategy2);
        assertEq(newStrategy1Prev, newStrategy2);
        assertEq(newStrategy1Next, address(0));
        assertEq(newStrategy2Prev, address(0));
        assertEq(newStrategy2Next, newStrategy1);
    }

    function test_CannotAddStrategyTwice() public {
        address newStrategy = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy, CAP, address(0));
        vm.expectRevert(IFarmDispatcher.FD_STRATEGY_EXISTS.selector);
        dispatcher.addStrategy(newStrategy, CAP, address(0));
    }

    function test_CannotAddStrategyAtInactivePosition() public {
        address newStrategy = makeAddr("newStrategy");
        vm.expectRevert(IFarmDispatcher.FD_INACTIVE_STRATEGY_POSITION.selector);
        dispatcher.addStrategy(newStrategy, CAP, vm.addr(5));
    }

    function test_AddManyStrategies() public {
        address newStrategy1 = address(createStrategyHelper());
        address newStrategy2 = address(createStrategyHelper());
        address[] memory strategies = new address[](2);
        uint256[] memory caps = new uint256[](2);
        strategies[0] = newStrategy1;
        strategies[1] = newStrategy2;
        caps[0] = CAP;
        caps[1] = CAP;

        dispatcher.addStrategies(strategies, caps, address(0));
        (, , , address zeroPrev, address zeroNext) = dispatcher.strategies(address(0));
        (, , , address firstPrev, address firstNext) = dispatcher.strategies(newStrategy1);
        (, , , address secondPrev, address secondNext) = dispatcher.strategies(newStrategy2);
        assertEq(zeroPrev, newStrategy2);
        assertEq(zeroNext, newStrategy1);
        assertEq(firstPrev, address(0));
        assertEq(firstNext, newStrategy2);
        assertEq(secondPrev, newStrategy1);
        assertEq(secondNext, address(0));
    }

    function test_AddManyStrategiesAtNPosition() public {
        address newStrategy1 = address(createStrategyHelper());
        address newStrategy2 = address(createStrategyHelper());
        address newStrategy3 = address(createStrategyHelper());
        address newStrategy4 = address(createStrategyHelper());
        address[] memory strategies = new address[](2);
        uint256[] memory caps = new uint256[](2);
        strategies[0] = newStrategy1;
        strategies[1] = newStrategy2;
        caps[0] = CAP;
        caps[1] = CAP;
        dispatcher.addStrategies(strategies, caps, address(0));
        strategies[0] = newStrategy3;
        strategies[1] = newStrategy4;
        dispatcher.addStrategies(strategies, caps, newStrategy1);
        (, , , address prev, address next) = dispatcher.strategies(address(0));
        assertEq(prev, newStrategy2);
        assertEq(next, newStrategy1);
        (, , , prev, next) = dispatcher.strategies(newStrategy1);
        assertEq(prev, address(0));
        assertEq(next, newStrategy3);
        (, , , prev, next) = dispatcher.strategies(newStrategy2);
        assertEq(prev, newStrategy4);
        assertEq(next, address(0));
        (, , , prev, next) = dispatcher.strategies(newStrategy3);
        assertEq(prev, newStrategy1);
        assertEq(next, newStrategy4);
        (, , , prev, next) = dispatcher.strategies(newStrategy4);
        assertEq(prev, newStrategy3);
        assertEq(next, newStrategy2);
    }

    function test_StrategiesMismatch() public {
        address newStrategy1 = makeAddr("newStrategy1");
        address newStrategy2 = makeAddr("newStrategy2");
        address[] memory strategies = new address[](2);
        uint256[] memory caps = new uint256[](1);
        strategies[0] = newStrategy1;
        strategies[1] = newStrategy2;
        caps[0] = CAP;
        vm.expectRevert(IFarmDispatcher.FS_STRATEGIES_MISMATCH.selector);
        dispatcher.addStrategies(strategies, caps, address(0));
    }

    function test_EmptyArrayOfStrategies() public {
        address[] memory strategies = new address[](0);
        uint256[] memory caps = new uint256[](0);
        vm.expectRevert(IFarmDispatcher.FS_EMPTY_STRATEGIES.selector);
        dispatcher.addStrategies(strategies, caps, address(0));
    }

    function test_AddStrategiesUnauthorized() public {
        address newStrategy1 = makeAddr("newStrategy1");
        address newStrategy2 = makeAddr("newStrategy2");

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.addStrategy(newStrategy1, CAP, address(0));

        address[] memory strategies = new address[](2);
        uint256[] memory caps = new uint256[](2);
        strategies[0] = newStrategy1;
        strategies[1] = newStrategy2;
        caps[0] = CAP;
        caps[1] = CAP;

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.addStrategies(strategies, caps, address(0));
    }

    function test_SetStrategyPosition() public {
        address newStrategy1 = address(createStrategyHelper());
        address newStrategy2 = address(createStrategyHelper());
        address[] memory strategies = new address[](2);
        uint256[] memory caps = new uint256[](2);
        strategies[0] = newStrategy1;
        strategies[1] = newStrategy2;
        caps[0] = CAP;
        caps[1] = CAP;

        dispatcher.addStrategies(strategies, caps, address(0));
        dispatcher.setStrategyPriority(newStrategy2, address(0));
        (, , , address zeroPrev, address zeroNext) = dispatcher.strategies(address(0));
        (, , , address firstPrev, address firstNext) = dispatcher.strategies(newStrategy1);
        (, , , address secondPrev, address secondNext) = dispatcher.strategies(newStrategy2);
        assertEq(zeroPrev, newStrategy1);
        assertEq(zeroNext, newStrategy2);
        assertEq(firstPrev, newStrategy2);
        assertEq(firstNext, address(0));
        assertEq(secondPrev, address(0));
        assertEq(secondNext, newStrategy1);
    }

    function test_SetStrategyPositionToItself() public {
        address newStrategy = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy, CAP, address(0));
        vm.expectRevert(IFarmDispatcher.FD_STRATEGY_PRIORITY_THE_SAME.selector);
        dispatcher.setStrategyPriority(newStrategy, newStrategy);
    }

    function test_SetStrategyPositionUnauthorized() public {
        address newStrategy = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy, CAP, address(0));
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.setStrategyPriority(newStrategy, address(0));
    }

    function test_SetStrategyPositionInactive() public {
        address newStrategy1 = makeAddr("newStrategy1");
        vm.expectRevert(IFarmDispatcher.FD_INACTIVE_STRATEGY.selector);
        dispatcher.setStrategyPriority(newStrategy1, address(0));
    }

    function test_SetStrategyPositionToInactive() public {
        address newStrategy = address(createStrategyHelper());
        dispatcher.addStrategy(newStrategy, CAP, address(0));
        vm.expectRevert(IFarmDispatcher.FD_INACTIVE_STRATEGY_POSITION.selector);
        dispatcher.setStrategyPriority(address(newStrategy), makeAddr("inactive"));
    }

    function test_Dispatch() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        dispatcher.dispatch();
        (, , uint256 totalDeposit, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit, CAP);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_DispatchInManyStrategies() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);
        IToken(workingAsset).mint(address(dispatcher), CAP * 2);
        dispatcher.dispatch();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, CAP);
        assertEq(totalDeposit2, CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), CAP);
        assertEq(dispatcher.balance(), CAP * 2);
    }

    function test_DispatchMoreThanCAP() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);
        IToken(workingAsset).mint(address(dispatcher), CAP * 3);
        dispatcher.dispatch();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, CAP);
        assertEq(totalDeposit2, CAP);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), CAP);
        assertEq(dispatcher.balance(), CAP * 3);
    }

    function test_DispatchLocalBalance() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP);
        dispatcher.dispatch();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit1, CAP);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_DispatchUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.dispatch();
    }

    function test_Withdraw() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        vm.startPrank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.withdraw(CAP);
        vm.stopPrank();
        (, , uint256 totalDeposit, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP);
        assertEq(dispatcher.balance(), 0);
    }

    function test_WithdrawFromManyStrategiesWithUnorderedBalances() public {
        address newStrategy3 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy3, 10e18, address(0));
        IToken(workingAsset).mint(address(dispatcher), 7e18);
        vm.prank(vaultAddress);
        dispatcher.dispatch();

        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy2, 10e18, address(0));
        IToken(workingAsset).mint(address(dispatcher), 1e18);
        vm.prank(vaultAddress);
        dispatcher.dispatch();

        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, 10e18, address(0));
        IToken(workingAsset).mint(address(dispatcher), 10e18);
        vm.prank(vaultAddress);
        dispatcher.dispatch();

        // Now the dispatcher has these strategies and withdraws in reverse order
        // Strategy1 - 10 tokens
        // Strategy2 - 1 tokens
        // Strategy3 - 7 tokens

        vm.prank(vaultAddress);
        dispatcher.withdraw(10e18);

        (, , uint256 totalDeposit3, , ) = dispatcher.strategies(newStrategy3);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit3, 0, "Strategy3 totalDeposit");
        assertEq(totalDeposit2, 0, "Strategy2 totalDeposit");
        assertEq(totalDeposit1, 8e18, "Strategy1 totalDeposit");

        // These are the actual checks
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), 10e18);
        assertEq(dispatcher.balance(), 8e18);

        // BaseFarmStrategy has no underlying farming strategy and the tokens reside in it.
        // On any withdraw it sends the whole balance. These checks are BaseFarmStrategy specific.
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 8e18, "Dispatcher balance");
        assertEq(IToken(workingAsset).balanceOf(newStrategy3), 0, "Strategy3 balance");
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), 0, "Strategy2 balance");
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0, "Strategy1 balance");
    }

    function test_WithdrawFromManyStrategies() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP * 2, address(0));
        dispatcher.addStrategy(newStrategy2, CAP * 2, newStrategy1);
        IToken(workingAsset).mint(address(dispatcher), CAP * 4);
        vm.startPrank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.withdraw(CAP * 3);
        vm.stopPrank();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, CAP);
        assertEq(totalDeposit2, 0);
        // Withdraw from the farm strategy returns the farm strategy balance. That is why it returns CAP * 2 instead of CAP
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP * 3);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_WithdrawFromLocalBalance() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP * 3);
        vm.startPrank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.withdraw(CAP);
        vm.stopPrank();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit1, CAP);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP);
        assertEq(dispatcher.balance(), CAP * 2);
    }

    function test_WithdrawFromLocalAndFromStrategy() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP * 3);
        vm.startPrank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.withdraw(CAP * 3);
        vm.stopPrank();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit1, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP * 3);
        assertEq(dispatcher.balance(), 0);
    }

    function test_WithdrawAsMuchAsPossible() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP * 2, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);

        IToken(workingAsset).mint(address(dispatcher), CAP * 3);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        // Simulate 100% loss from the first strategy
        vm.prank(address(dispatcher));
        IFarmStrategy(newStrategy1).withdraw(CAP * 2);
        // Transfer the loss to the vault address
        vm.prank(address(dispatcher));
        IToken(workingAsset).transfer(vaultAddress, CAP * 2);
        vm.prank(vaultAddress);
        dispatcher.withdraw(CAP * 2);
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, CAP);
        assertEq(totalDeposit2, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP * 3);
        assertEq(dispatcher.balance(), 0);
    }

    function test_WithdrawMoreThenDeposited() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        vm.startPrank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.withdraw(CAP * 2);
        vm.stopPrank();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(totalDeposit1, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP);
        assertEq(dispatcher.balance(), 0);
    }

    function test_NonVaultWithdraws() public {
        vm.expectRevert(IFarmDispatcher.FD_ONLY_VAULT.selector);
        dispatcher.withdraw(CAP);
    }

    function test_IncreaseMaxCAP() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.setStrategyMax(newStrategy1, CAP * 2);

        (, uint256 strategyCAP, , , ) = dispatcher.strategies(newStrategy1);
        assertEq(strategyCAP, CAP * 2);
    }

    function test_DecreaseMaxCAPPartially() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP * 2, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP * 2);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.setStrategyMax(newStrategy1, CAP);
        (, uint256 strategyCap, uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(strategyCap, CAP);
        assertEq(totalDeposit1, CAP);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP * 2);
        // Withdraw from the farm strategy returns the farm strategy balance. That is why it returns CAP * 2 instead of CAP
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(dispatcher.balance(), CAP * 2);
    }

    function test_DecreaseMaxCAPEntirely() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP * 2, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP * 2);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.setStrategyMax(newStrategy1, 0);
        (, uint256 strategyCAP, uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        assertEq(strategyCAP, 0);
        assertEq(totalDeposit1, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP * 2);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(dispatcher.balance(), CAP * 2);
    }

    function test_AdjustsCapUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.setStrategyMax(vm.addr(1), CAP);
    }

    function test_AdjustCAPForInactiveStrategy() public {
        vm.expectRevert(IFarmDispatcher.FD_INACTIVE_STRATEGY.selector);
        dispatcher.setStrategyMax(vm.addr(1), CAP);
    }

    function test_DeactivateStrategy_Withdraw() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.deactivateStrategy(newStrategy1, true);
        (bool active, uint256 maxAmount, uint256 totalDeposit, , ) = dispatcher.strategies(newStrategy1);
        assertEq(active, false);
        assertEq(maxAmount, 0);
        assertEq(totalDeposit, 0);
        (, , , address prev, address next) = dispatcher.strategies(address(0));
        assertEq(prev, address(0));
        assertEq(next, address(0));
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_DeactivateStrategy_NoWithdraw() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        IToken(workingAsset).mint(address(dispatcher), CAP);
        vm.prank(vaultAddress);
        dispatcher.dispatch();
        dispatcher.deactivateStrategy(newStrategy1, false);
        (bool active, uint256 maxAmount, uint256 totalDeposit, , ) = dispatcher.strategies(newStrategy1);
        assertEq(active, false);
        assertEq(maxAmount, CAP);
        assertEq(totalDeposit, CAP);
        (, , , address prev, address next) = dispatcher.strategies(address(0));
        assertEq(prev, address(0));
        assertEq(next, address(0));
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), CAP);
        assertEq(dispatcher.balance(), 0);
    }

    function test_DeactivatesStrategyUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        dispatcher.deactivateStrategy(vm.addr(1), false);
    }

    function test_DeactivateInactiveStrategy() public {
        vm.expectRevert(IFarmDispatcher.FD_INACTIVE_STRATEGY.selector);
        dispatcher.deactivateStrategy(vm.addr(1), false);
    }

    function test_DeactivateZeroStrategy() public {
        vm.expectRevert(IFarmDispatcher.FD_ZERO_STRATEGY_REMOVAL.selector);
        dispatcher.deactivateStrategy(address(0), false);
    }

    function test_SkipRevertStrategyDeposit() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);

        IToken(workingAsset).mint(address(dispatcher), CAP);
        // Simulate revert
        vm.mockCallRevert(newStrategy1, abi.encodeWithSelector(IFarmStrategy.deposit.selector, CAP), "REVERT_MESSAGE");

        dispatcher.dispatch();
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, 0);
        assertEq(totalDeposit2, CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), CAP);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_SkipRevertStrategyWithdraw() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);

        IToken(workingAsset).mint(address(dispatcher), CAP * 2);
        dispatcher.dispatch();
        // Simulate revert
        vm.mockCallRevert(newStrategy2, abi.encodeWithSelector(IFarmStrategy.withdraw.selector, CAP), "REVERT_MESSAGE");
        vm.prank(vaultAddress);
        dispatcher.withdraw(CAP);
        (, , uint256 totalDeposit1, , ) = dispatcher.strategies(newStrategy1);
        (, , uint256 totalDeposit2, , ) = dispatcher.strategies(newStrategy2);
        assertEq(totalDeposit1, 0);
        assertEq(totalDeposit2, CAP);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), CAP);
        assertEq(IToken(workingAsset).balanceOf(vaultAddress), CAP);
        assertEq(dispatcher.balance(), CAP);
    }

    function test_BalanceAvailable() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        address newStrategy3 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);
        dispatcher.addStrategy(newStrategy3, CAP, newStrategy2);

        // Simulate revert
        vm.mockCallRevert(
            newStrategy1,
            abi.encodeWithSelector(IFarmStrategy.balanceAvailable.selector),
            "REVERT_MESSAGE"
        );
        vm.mockCallRevert(
            newStrategy3,
            abi.encodeWithSelector(IFarmStrategy.balanceAvailable.selector),
            "REVERT_MESSAGE"
        );

        (uint256 balance, uint256 revertedStrategies) = dispatcher.balanceAvailable();
        assertEq(balance, 0);
        assertEq(revertedStrategies, 5);
        assertTrue(revertedStrategies & (2 ** 0) > 0); // strategy 1 has reverted
        assertTrue(revertedStrategies & (2 ** 2) > 0); // strategy 3 has reverted
        assertEq(revertedStrategies & (2 ** 1), 0); // strategy 2 has not reverted
    }

    function test_GetNextStrategy() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));
        dispatcher.addStrategy(newStrategy1, CAP, address(0));

        assertEq(dispatcher.getNextStrategy(address(0)), newStrategy1);
        assertEq(dispatcher.getNextStrategy(newStrategy1), address(0));
    }

    function test_RecognizeRewards() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);

        uint256 reward = 1e6;
        IToken(workingAsset).mint(newStrategy1, reward);
        IToken(workingAsset).mint(newStrategy2, reward);

        (uint256 rewards, uint256 errors) = dispatcher.recogniseRewards();

        assertEq(rewards, reward * 2);
        assertEq(errors, 0);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), rewards);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), 0);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), 0);
    }

    function test_RecognizeRewardsWithErrors() public {
        address newStrategy1 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        // Simulate rewards recognition revert
        vm.mockCallRevert(
            newStrategy1,
            abi.encodeWithSelector(IFarmStrategy.recogniseRewardsInBase.selector),
            "REVERT_MESSAGE"
        );

        address newStrategy2 = BaseGetter.getBaseFarmStrategy(workingAsset, address(dispatcher), address(dispatcher));

        dispatcher.addStrategy(newStrategy1, CAP, address(0));
        dispatcher.addStrategy(newStrategy2, CAP, newStrategy1);

        uint256 reward = 1e6;
        IToken(workingAsset).mint(newStrategy1, reward);
        IToken(workingAsset).mint(newStrategy2, reward);

        (uint256 rewards, uint256 errors) = dispatcher.recogniseRewards();

        assertEq(rewards, reward);
        assertEq(errors, 1);
        assertEq(IToken(workingAsset).balanceOf(address(dispatcher)), rewards);
        assertEq(IToken(workingAsset).balanceOf(newStrategy1), reward);
        assertEq(IToken(workingAsset).balanceOf(newStrategy2), 0);
    }

    function test_SetStrategyMaxZeroStrategy() public {
        vm.expectRevert(IFarmDispatcher.FD_ZERO_STRATEGY_REMOVAL.selector);
        dispatcher.setStrategyMax(address(0), 100);
    }
}
