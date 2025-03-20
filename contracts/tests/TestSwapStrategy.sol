// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../libraries/uniswap-v3/TransferHelper.sol";

/**
 * @title TestSwapStrategy
 * @dev TestSwapStrategy contract for tests purpose ONLY
 * @dev Process swaps between predefinded pairs
 * @author Altitude Labs
 **/

contract TestSwapStrategy {
    uint256 public price;
    uint256 public decimals;

    constructor(uint256 tokenDec) {
        decimals = 10**tokenDec;
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }

    function swapInBase(
        address assetFrom,
        address assetTo,
        uint256 amount
    ) external returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(assetFrom, msg.sender, address(this), amount);

        uint256 returnAmount = (decimals * amount) / price;
        returnAmount -= ((returnAmount * 5) / 100); // slippage
        TransferHelper.safeTransfer(assetTo, msg.sender, returnAmount);

        return returnAmount;
    }

    function getMinimumAmountOut(
        address, // assetFrom
        address, // assetTo
        uint256 amount,
        uint256 // slippage
    ) external view returns (uint256, uint256) {
        return ((decimals * amount) / price, 0);
    }
}
