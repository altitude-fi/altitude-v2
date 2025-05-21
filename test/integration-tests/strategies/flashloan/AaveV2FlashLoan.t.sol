// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {FlashLoanTest} from "./FlashLoanTest.sol";
import {Aavev2FlashLoanStrategy} from "../../../../contracts/strategies/flashloan/Aavev2FlashLoanStrategy.sol";
import {IAaveLendingPoolAddressesProvider} from "../../../../contracts/interfaces/external/strategy/lending/Aave/ILendingPoolAddressProvider.sol";

contract AaveV2FlashLoanTest is FlashLoanTest {
    function setUp() public override {
        super.setUp();

        // Aave V2 flashloan fee is 0.09%
        feeExpected = 9e4;

        flashLoanStrategy = new Aavev2FlashLoanStrategy(IAaveLendingPoolAddressesProvider(Constants.aave_v2_Provider));
    }

    function test_CorrectInitialization() public view virtual {
        assertEq(
            address(Aavev2FlashLoanStrategy(address(flashLoanStrategy)).AAVE_LENDING_POOL_V2()),
            Constants.aave_v2_Pool
        );
    }
}
