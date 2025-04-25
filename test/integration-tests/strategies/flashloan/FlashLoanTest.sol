// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Constants} from "../../../../scripts/deployer/Constants.sol";
import {IToken} from "../../../interfaces/IToken.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";
import {ForkTest} from "../../../ForkTest.sol";
import {FlashLoan} from "../../../../contracts/libraries/utils/FlashLoan.sol";
import {IFlashLoanStrategy} from "../../../../contracts/interfaces/internal/flashloan/IFlashLoanStrategy.sol";

abstract contract FlashLoanTest is ForkTest, TokensGenerator {
    address public flashLoanReceiver;
    IFlashLoanStrategy public flashLoanStrategy;

    // Expected fee in total value in regards FLASH_LOAN_AMOUNT
    uint256 public feeExpected;

    // In USDC
    uint256 public FLASH_LOAN_AMOUNT = 100e6;

    function test_FlashLoan() public {
        flashLoanStrategy.flashLoan(
            FlashLoan.Info({
                targetContract: address(this),
                asset: Constants.USDC,
                amount: FLASH_LOAN_AMOUNT,
                data: abi.encode(address(0), FLASH_LOAN_AMOUNT)
            })
        );

        assertEq(IToken(Constants.USDC).balanceOf(address(this)), FLASH_LOAN_AMOUNT);
    }

    /// @dev That is a function the flashloan contract will return to in order to collect the loaned amount
    /// @dev For test purposes only.
    function flashLoanCallback(bytes calldata params, uint256 migrationFee) external {
        (, uint256 loanAmount) = abi.decode(params, (address, uint256));

        mintToken(Constants.USDC, address(flashLoanStrategy), loanAmount + migrationFee);

        assertEq(msg.sender, address(flashLoanStrategy));
        assertEq(migrationFee, feeExpected);
    }
}
