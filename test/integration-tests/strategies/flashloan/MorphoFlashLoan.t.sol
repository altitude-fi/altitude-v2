pragma solidity 0.8.28;

import {IMorpho} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {FlashLoanTest} from "./FlashLoanTest.sol";
import {MorphoFlashLoanStrategy} from "../../../../contracts/strategies/flashloan/MorphoFlashLoanStrategy.sol";

contract MorhoFlashLoanTest is FlashLoanTest {
    function setUp() public override {
        super.setUp();

        // Morpho flashloan fee is 0
        feeExpected = 0;

        flashLoanStrategy = new MorphoFlashLoanStrategy(IMorpho(Constants.morpho_Pool));
    }

    function test_CorrectInitialization() public view virtual {
        assertEq(address(MorphoFlashLoanStrategy(address(flashLoanStrategy)).MORPHO()), Constants.morpho_Pool);
    }
}
