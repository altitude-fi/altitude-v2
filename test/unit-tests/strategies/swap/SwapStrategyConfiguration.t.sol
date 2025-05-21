// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../../../contracts/strategies/swap/SwapStrategyConfiguration.sol";
import {Constants} from "../../../../scripts/deployer/Constants.sol";

contract SwapStrategyConfigurationTest is Test {
    SwapStrategyConfiguration public swapStrategyConfig;

    function setUp() public {
        // Deploy contract with zero address as initial swap strategy
        swapStrategyConfig = new SwapStrategyConfiguration(address(0));
    }

    function testInitialConstruction() public view {
        assertEq(address(swapStrategyConfig.swapStrategy()), address(0));
    }

    function testSetSwapStrategy() public {
        address newStrategy = vm.addr(2);
        swapStrategyConfig.setSwapStrategy(newStrategy);

        assertEq(address(swapStrategyConfig.swapStrategy()), newStrategy);
    }

    function testSetSwapStrategyUnauthorized() public {
        address newStrategy = vm.addr(2);

        // Switch to non-owner account
        vm.prank(vm.addr(1));

        // Expect revert when non-owner tries to set strategy
        vm.expectRevert("Ownable: caller is not the owner");
        swapStrategyConfig.setSwapStrategy(newStrategy);
    }
}
