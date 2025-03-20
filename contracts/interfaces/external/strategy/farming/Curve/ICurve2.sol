// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "./ICurve.sol";

interface ICurve2 is ICurve {
    function price_oracle() external view returns (uint256 price);

    function add_liquidity(uint256[2] calldata amounts, uint256 minMintAmount) external;

    function remove_liquidity(uint256 amount, uint256[2] calldata minUAmounts) external;

    function remove_liquidity_imbalance(uint256[2] calldata minUAmounts, uint256 maxBurnAmount) external;

    function underlying_coins() external returns (address[2] memory);

    function calc_token_amount(uint256[2] memory amounts, bool isDeposit) external view returns (uint256);
}
