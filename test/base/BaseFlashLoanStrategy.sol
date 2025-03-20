// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {TokensGenerator} from "../utils/TokensGenerator.sol";
import {FlashLoan} from "../../contracts/libraries/utils/FlashLoan.sol";
import {IFlashLoanCallback} from "../../contracts/interfaces/internal/strategy/IFlashLoanCallback.sol";

contract BaseFlashLoanStrategy is TokensGenerator {
    uint256 public FEE;

    function flashLoan(FlashLoan.Info calldata info) external {
        mintToken(info.asset, info.targetContract, info.amount);
        IFlashLoanCallback(info.targetContract).flashLoanCallback(info.data, FEE);
    }

    // For test purposes
    function setFee(uint256 fee) public {
        FEE = fee;
    }
}
