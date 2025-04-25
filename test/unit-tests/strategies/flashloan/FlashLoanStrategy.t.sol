// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {FlashLoan} from "../../../../contracts/libraries/utils/FlashLoan.sol";
import {FlashLoanStrategy} from "../../../../contracts/strategies/flashloan/FlashLoanStrategy.sol";
import {IFlashLoanStrategy} from "../../../../contracts/interfaces/internal/flashloan/IFlashLoanStrategy.sol";

/// @dev Contract for test purposes only
contract FlashLoanTest is FlashLoanStrategy {
    bool private toReentrant;

    function setReentrancy() public {
        toReentrant = true;
    }

    function _processFlashLoan(FlashLoan.Info calldata info) internal override {
        // Simulate reentrancy just to test flashloan MISS_STEP
        if (toReentrant) {
            FlashLoanTest(address(this)).flashLoan(info);
        }
    }

    function onFlashLoanReceive() external {
        _onFlashLoanReceive(0, 0, address(0));
    }
}

contract FlashLoanStrategyTest is Test {
    using stdStorage for StdStorage;

    FlashLoanTest public flashLoan;

    function setUp() public {
        flashLoan = new FlashLoanTest();
    }

    function test_FlashLoanMissStep() public {
        flashLoan.setReentrancy();
        vm.expectRevert(IFlashLoanStrategy.FLS_MISSTEP.selector);
        flashLoan.flashLoan(FlashLoan.Info(address(this), address(0), 0, ""));
    }

    function test_FlashLoanWrongTarget() public {
        vm.expectRevert(IFlashLoanStrategy.FLS_WRONG_TARGET.selector);
        flashLoan.flashLoan(FlashLoan.Info(address(0), address(0), 0, ""));
    }

    function test_FlashLoanReceiveMissStep() public {
        vm.expectRevert(IFlashLoanStrategy.FLS_MISSTEP.selector);
        flashLoan.onFlashLoanReceive();
    }
}
