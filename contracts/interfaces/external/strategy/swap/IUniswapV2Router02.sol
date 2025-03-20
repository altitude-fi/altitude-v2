// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IUniswapV2Router02 {
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}
