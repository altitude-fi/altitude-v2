// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../libraries/utils/FlashLoan.sol";
import {FlashLoanStrategy} from "./FlashLoanStrategy.sol";
import {IFlashLoanReceiver} from "../../interfaces/external/strategy/lending/Aave/IFlashLoanReceiver.sol";
import {IAaveLendingPool} from "../../interfaces/external/strategy/lending/Aave/v2/ILendingPool.sol";
import {IAaveLendingPoolAddressesProvider} from "../../interfaces/external/strategy/lending/Aave/ILendingPoolAddressProvider.sol";

/**
 * @title Aavev2FlashLoanStrategy
 * @dev Contract for integrating with Aave Flashloans
 * @author Altitude Labs
 **/

contract Aavev2FlashLoanStrategy is IFlashLoanReceiver, FlashLoanStrategy {
    // The Aave Lending Pool V2
    IAaveLendingPool public immutable AAVE_LENDING_POOL_V2;

    constructor(IAaveLendingPoolAddressesProvider provider) {
        AAVE_LENDING_POOL_V2 = IAaveLendingPool(provider.getLendingPool());
    }

    /// @notice Executes AAV2 V2 flashloan
    /// @param info The parameters for the flashloan
    function _processFlashLoan(FlashLoan.Info calldata info) internal override {
        address[] memory assets = new address[](1);
        assets[0] = address(info.asset);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = info.amount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt, 1 = stable, 2 = variable

        AAVE_LENDING_POOL_V2.flashLoan(
            address(this), // receiverAddress
            assets,
            amounts,
            modes,
            address(0), // onBehalfOf
            "", // Byte data to pass on. Don't trust the provider.
            0 // referralCode
        );
    }

    /// @notice This function is called by Aave FlashLoan when sending loaned asset amount
    /// @param amounts The amounts being flash loaned
    /// @param premiums The premiums being flash loaned
    /// @return true if successful
    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address, /* initiator */
        bytes calldata /* params */
    ) external override returns (bool) {
        _onFlashLoanReceive(amounts[0], premiums[0], address(AAVE_LENDING_POOL_V2));
        return true;
    }
}
