// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ILenderStrategy} from "../../../contracts/interfaces/internal/strategy/lending/ILenderStrategy.sol";
import {HealthFactorCalculator} from "../../../contracts/libraries/utils/HealthFactorCalculator.sol";

contract HealthFactorCalculatorTest is Test {
    function setUp() public {}

    function test_HealthFactor() public pure {
        // Test scenario with:
        // Collateral: 100 ETH = $2000 = $200,000
        // Liquidation threshold: 80%
        // Borrowed: $100,000
        uint256 collateralValueInUsd = 200_000e18; // $200,000 with 18 decimals
        uint256 liquidationThreshold = 0.8e18; // 80% with 18 decimals
        uint256 borrowedAmountInUsd = 100_000e18; // $100,000 with 18 decimals

        uint256 healthFactor = HealthFactorCalculator.healthFactor(
            liquidationThreshold,
            collateralValueInUsd,
            borrowedAmountInUsd
        );

        // Expected health factor: (200,000 * 0.8) / 100,000 = 1.6
        // With 18 decimals: 1.6e18
        uint256 expectedHealthFactor = 1.6e18;

        assertEq(healthFactor, expectedHealthFactor);
    }

    function test_HealthFactorWithZeroBorrow() public pure {
        assertEq(HealthFactorCalculator.healthFactor(0.8e18, 200_000e18, 0), type(uint256).max);
    }

    function test_IfPositionIsHealthy() public {
        // Mock the convertToBase function to return 200_000e18 representing 1:1 price
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ILenderStrategy.convertToBase.selector),
            abi.encode(200_000e18)
        );

        assertEq(
            HealthFactorCalculator.isPositionHealthy(
                address(this),
                makeAddr("supply"),
                makeAddr("borrow"),
                0.8e18,
                200_000e18,
                100_000e18
            ),
            true
        );
    }

    function test_IfPositionIsNotHealthy() public {
        // Mock the convertToBase function to return 100_000e18 representing 1:0.5 price
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ILenderStrategy.convertToBase.selector),
            abi.encode(100_000e18)
        );

        assertEq(
            HealthFactorCalculator.isPositionHealthy(
                address(this),
                makeAddr("supply"),
                makeAddr("borrow"),
                0.8e18,
                200_000e18,
                100_000e18
            ),
            false
        );
    }

    function test_AvailableBorrow() public pure {
        assertEq(HealthFactorCalculator.availableBorrow(0.8e18, 200_000e18, 100_000e18), 60_000e18);
    }

    function test_NoAvailableBorrow() public pure {
        assertEq(HealthFactorCalculator.availableBorrow(0.8e18, 200_000e18, 180_000e18), 0);
    }

    function test_TargetBorrow() public {
        // Mock the convertToBase function to return 100_000e18 representing 1:1 price
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(ILenderStrategy.convertToBase.selector),
            abi.encode(200_000e18)
        );

        assertEq(
            HealthFactorCalculator.targetBorrow(
                address(this),
                makeAddr("supply"),
                makeAddr("borrow"),
                0.8e18,
                200_000e18
            ),
            160_000e18
        );
    }
}
