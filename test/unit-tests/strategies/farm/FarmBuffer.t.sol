pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {IToken} from "../../../interfaces/IToken.sol";
import {BaseGetter} from "../../../base/BaseGetter.sol";
import "../../../../contracts/strategies/farming/FarmBuffer.sol";

contract FarmBufferTest is Test {
    FarmBuffer public farmBuffer;
    address public workingAsset;
    uint256 public constant BUFFER = 1e6;

    function setUp() public {
        workingAsset = BaseGetter.getBaseERC20(18);
        farmBuffer = new FarmBuffer(workingAsset);
    }

    function test_CorrectInitialization() public view {
        assertEq(farmBuffer.token(), workingAsset);
    }

    function test_DeployingWithZeroAddress() public {
        vm.expectRevert(IFarmBuffer.FM_ZERO_ADDRESS.selector);
        new FarmBuffer(address(0));
    }

    function test_FillBuffer() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        farmBuffer.empty(BUFFER);
        IToken(workingAsset).approve(address(farmBuffer), BUFFER);
        farmBuffer.fill(BUFFER);

        assertEq(farmBuffer.capacityMissing(), 0);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), BUFFER);
    }

    function test_OverfillBuffer() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        IToken(workingAsset).mint(address(this), BUFFER);
        IToken(workingAsset).approve(address(farmBuffer), BUFFER);
        farmBuffer.fill(BUFFER);

        assertEq(farmBuffer.capacityMissing(), 0);
        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), BUFFER);
    }

    function test_FillBufferUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmBuffer.fill(BUFFER);
    }

    function test_EmptyBuffer() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        farmBuffer.empty(BUFFER);

        assertEq(farmBuffer.capacityMissing(), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER);
    }

    function test_OverEmptyBuffer() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        farmBuffer.empty(BUFFER);
        farmBuffer.empty(BUFFER);

        assertEq(farmBuffer.capacityMissing(), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), 0);
        assertEq(IToken(workingAsset).balanceOf(address(this)), BUFFER);
    }

    function test_EmptyBufferUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmBuffer.empty(BUFFER);
    }

    function test_IncreaseBufferSize() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);

        assertEq(farmBuffer.capacityMissing(), 0);
        assertEq(farmBuffer.size(), BUFFER);
        assertEq(farmBuffer.capacity(), BUFFER);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), BUFFER);
    }

    function test_IncreaseBufferSizeWithNoFunds() public {
        vm.expectRevert(IFarmBuffer.FM_WRONG_INCREASE.selector);
        farmBuffer.increaseSize(BUFFER);
    }

    function test_IncreaseBufferSizeUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmBuffer.increaseSize(BUFFER);
    }

    function test_DecreaseBufferSize() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        farmBuffer.decreaseSize(BUFFER, vm.addr(2));

        assertEq(farmBuffer.capacityMissing(), 0);
        assertEq(farmBuffer.size(), 0);
        assertEq(farmBuffer.capacity(), 0);
        assertEq(IToken(workingAsset).balanceOf(address(farmBuffer)), 0);
        assertEq(IToken(workingAsset).balanceOf(vm.addr(2)), BUFFER);
    }

    function test_DecreaseBufferSizeWithNotEnoughCapacity() public {
        IToken(workingAsset).mint(address(farmBuffer), BUFFER);

        farmBuffer.increaseSize(BUFFER);
        farmBuffer.empty(BUFFER / 2);

        vm.expectRevert(IFarmBuffer.FM_WRONG_DECREASE.selector);
        farmBuffer.decreaseSize(BUFFER, vm.addr(2));
    }

    function test_DecreaseBufferSizeUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Ownable: caller is not the owner");
        farmBuffer.decreaseSize(BUFFER, vm.addr(2));
    }

    function test_ZeroAddressArgument() public {
        vm.expectRevert(IFarmBuffer.FM_ZERO_ADDRESS.selector);
        farmBuffer.decreaseSize(1, address(0));
        vm.expectRevert(IFarmBuffer.FM_ZERO_ADDRESS.selector);
        farmBuffer.decreaseCapacity(address(0));
    }
}
