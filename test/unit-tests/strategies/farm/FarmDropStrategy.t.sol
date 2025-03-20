pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import {FarmStrategy} from "../../../../contracts/strategies/farming/strategies/FarmStrategy.sol";
import {FarmDropStrategy} from "../../../../contracts/strategies/farming/strategies/FarmDropStrategy.sol";
import {IFarmStrategy} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmStrategy.sol";
import {IFarmDropStrategy} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmDropStrategy.sol";
import {IFarmDispatcher} from "../../../../contracts/interfaces/internal/strategy/farming/IFarmDispatcher.sol";

contract FarmProvider {
    uint256 public dropPercentage;
    uint256 public increasePercentage;
    address public farmAsset;
    uint256 public amountDeposited;

    constructor(address farmAsset_) {
        farmAsset = farmAsset_;
    }

    function deposit(uint256 amount) public {
        IToken(farmAsset).transferFrom(msg.sender, address(this), amount);
        if (dropPercentage > 0) {
            amountDeposited += amount - (amount * dropPercentage) / 100;
        } else if (increasePercentage > 0) {
            amountDeposited += amount + (amount * increasePercentage) / 100;
        } else {
            amountDeposited += amount;
        }
    }

    function setDropPercentage(uint256 percentage) public {
        dropPercentage = percentage;
    }

    function setIncreasePercentage(uint256 percentage) public {
        increasePercentage = percentage;
    }

    // Externally set drop or increase
    function setAmountDeposited(uint256 amount) public {
        amountDeposited = amount;
    }

    function withdraw(uint256 amount) public {
        IToken(farmAsset).transfer(msg.sender, amount);
    }

    function balance() public view returns (uint256) {
        return amountDeposited;
    }
}

contract DropStrategy is FarmDropStrategy {
    uint256 public dropPerc;
    uint256 public incrPerc;
    FarmProvider public farmProvider;

    constructor(
        address farmAssetAddress,
        address farmDispatcherAddress,
        address rewardsAddress,
        address swapStrategyAddress
    ) FarmDropStrategy(farmAssetAddress, farmDispatcherAddress, rewardsAddress, swapStrategyAddress) {
        farmProvider = new FarmProvider(farmAssetAddress);
    }

    function balance() public view override(IFarmStrategy, FarmStrategy) returns (uint256) {
        return farmProvider.balance();
    }

    function _getFarmAssetAmount() internal pure override returns (uint256) {
        return 0;
    }

    function _deposit(uint256 amount) internal override {
        IToken(farmAsset).approve(address(farmProvider), amount);
        farmProvider.deposit(amount);
    }

    function _withdraw(uint256 amount) internal override {
        farmProvider.withdraw(amount);
    }

    function _emergencySwap(address[] calldata assets) internal override {}

    function _emergencyWithdraw() internal override {}
}

contract FarmDropStrategyTest is Test {
    DropStrategy public farmStrategy;
    IToken public workingAsset;

    function setUp() public {
        workingAsset = IToken(BaseGetter.getBaseERC20(18));
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(IFarmDispatcher.asset.selector),
            abi.encode(address(workingAsset))
        );
        farmStrategy = new DropStrategy(address(workingAsset), address(this), address(this), address(0));

        farmStrategy.setDropThreshold(1e18);
    }

    function test_SetDropThreshold() public {
        farmStrategy.setDropThreshold(1e18);
        assertEq(farmStrategy.dropThreshold(), 1e18);
    }

    function test_SetDropThresholdOutOfBounds() public {
        vm.expectRevert(IFarmDropStrategy.FDS_OUT_OF_BOUNDS.selector);
        farmStrategy.setDropThreshold(1e18 + 1);
    }

    function test_SetDropThresholdUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        farmStrategy.setDropThreshold(1e18);
    }

    function test_DepositDrop() public {
        farmStrategy.farmProvider().setDropPercentage(50);

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 5e17);

        deposit = 15e17;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 6875e14);
    }

    function test_DepositIncrease() public {
        farmStrategy.farmProvider().setIncreasePercentage(50); // 50% increase

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 0);

        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 0);
    }

    function test_DepositDropRecovery() public {
        farmStrategy.farmProvider().setDropPercentage(50); // 50% drop

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        deposit = 15e17;
        farmStrategy.farmProvider().setDropPercentage(0);
        farmStrategy.farmProvider().setIncreasePercentage(25); // 25% increase
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 40625e13);
    }

    function test_100PercentDrop() public {
        farmStrategy.farmProvider().setDropPercentage(100); // 100% drop

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 1e18);
    }

    function test_DepositDropHigherThanThreshold() public {
        farmStrategy.setDropThreshold(1e16); // 1% threshold

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        // Simulate external drop
        farmStrategy.farmProvider().setAmountDeposited(5e17); // 50% drop
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        vm.expectRevert();
        farmStrategy.deposit(deposit);
    }

    function test_WithdrawDrop() public {
        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        // Simulate drop in between deposit and withdraw
        farmStrategy.farmProvider().setAmountDeposited(5e17); // 50% drop
        farmStrategy.withdraw(deposit / 2);

        assertEq(farmStrategy.dropPercentage(), 5e17);
    }

    function test_WithdrawDropHigherThanThreshold() public {
        farmStrategy.setDropThreshold(1e16); // 1% threshold

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        farmStrategy.farmProvider().setAmountDeposited(5e17); // 50% drop
        farmStrategy.setDropThreshold(1e16);

        vm.expectRevert();
        farmStrategy.withdraw(deposit / 2);
    }

    function test_EmergencyWithdrawDrop() public {
        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        // Simulate drop in between deposit and emergencyWithdraw
        farmStrategy.farmProvider().setAmountDeposited(5e17); // 50% drop
        farmStrategy.emergencyWithdraw();

        assertEq(farmStrategy.dropPercentage(), 5e17);
    }

    function test_EmergencySwapDrop() public {
        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);
        farmStrategy.emergencyWithdraw();

        // Simulate drop in between deposit and emergencySwap
        farmStrategy.farmProvider().setAmountDeposited(5e17); // 50% drop
        farmStrategy.emergencySwap(new address[](0));

        assertEq(farmStrategy.dropPercentage(), 5e17);
    }

    function test_CurrentDropPercentage() public {
        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        farmStrategy.farmProvider().setAmountDeposited(1e17); // 90% drop
        assertEq(farmStrategy.currentDropPercentage(), 9e17);
    }

    function test_Reset() public {
        farmStrategy.farmProvider().setDropPercentage(10); // 10% drop

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        farmStrategy.reset();
        assertEq(farmStrategy.dropPercentage(), 0);
    }

    function test_ResetUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        farmStrategy.reset();
    }

    function test_RecogniseRewardsRecoversLoss() public {
        farmStrategy.farmProvider().setDropPercentage(10); // 10% drop

        uint256 deposit = 1e18;
        workingAsset.mint(address(this), deposit);
        workingAsset.approve(address(farmStrategy), deposit);
        farmStrategy.deposit(deposit);

        assertEq(farmStrategy.dropPercentage(), 1e17);

        // Simulate rewards
        farmStrategy.farmProvider().setAmountDeposited(deposit);

        farmStrategy.recogniseRewardsInBase();

        assertEq(farmStrategy.dropPercentage(), 0);
    }
}
