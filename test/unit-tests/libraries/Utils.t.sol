// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Utils} from "../../../contracts/libraries/utils/Utils.sol";

contract UtilsTest is Test {
    function setUp() public {}

    function test_CalcBalanceAtIndex() public pure {
        assertEq(Utils.calcBalanceAtIndex(100e18, 1, 2), 200e18);
    }

    function test_CalcBalanceAtIndexZeroBalance() public pure {
        assertEq(Utils.calcBalanceAtIndex(0, 1, 2), 0);
    }

    function test_CalcBalanceAtIndexZeroIndex() public pure {
        assertEq(Utils.calcBalanceAtIndex(100e18, 0, 2), 100e18);
    }

    function test_DivZeroNumerator() public pure {
        assertEq(Utils.divRoundingUp(0, 1), 0);
    }

    function test_DivZeroDenominator() public pure {
        assertEq(Utils.divRoundingUp(1, 0), 0);
    }

    function test_DivZeroResult() public pure {
        assertEq(Utils.divRoundingUp(1, 2), 0);
    }

    function test_DiExactDivision() public pure {
        assertEq(Utils.divRoundingUp(100, 2), 50);
    }

    function test_DivRoundingUp() public pure {
        assertEq(Utils.divRoundingUp(100, 3), 34);
    }

    function test_ScaleAmountTargetDecimalsHigher() public pure {
        assertEq(Utils.scaleAmount(100, 18, 20), 10000);
    }

    function test_ScaleAmountTargetDecimalsLower() public pure {
        assertEq(Utils.scaleAmount(100, 20, 18), 1);
    }

    function test_ScaleAmountSameDecimals() public pure {
        assertEq(Utils.scaleAmount(100, 18, 18), 100);
    }

    function test_SubOrZero() public pure {
        assertEq(Utils.subOrZero(100, 50), 50);
    }

    function test_SubOrZeroUnderflow() public pure {
        assertEq(Utils.subOrZero(50, 100), 0);
    }
}
