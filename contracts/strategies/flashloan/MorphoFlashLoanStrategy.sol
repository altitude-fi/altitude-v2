// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../libraries/utils/FlashLoan.sol";
import {FlashLoanStrategy} from "./FlashLoanStrategy.sol";
import {IMorpho} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

/**
 * @title MorphoFlashLoanStrategy
 * @dev Contract for integrating with Morpho Flashloans
 * @author Altitude Labs
 **/

contract MorphoFlashLoanStrategy is IMorphoFlashLoanCallback, FlashLoanStrategy {
    // The Morpho flashloan provider
    IMorpho public immutable MORPHO;

    constructor(IMorpho newMorpho) {
        MORPHO = newMorpho;
    }

    /// @notice Executes Morpho flashloan
    /// @param info The parameters for the flashloan
    function _processFlashLoan(FlashLoan.Info calldata info) internal override {
        MORPHO.flashLoan(
            info.asset,
            info.amount,
            "" // Byte data to pass on. Don't trust the provider.
        );
    }

    /// @notice This function is called by Morpho FlashLoan when sending loaned asset amount
    /// @param amount The amount being flash loaned
    function onMorphoFlashLoan(uint256 amount, bytes calldata /* params */) external override {
        // Execute flashloan custom logic
        _onFlashLoanReceive(amount, 0, address(MORPHO));
    }
}
