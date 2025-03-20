// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "./ICurve.sol";

interface ICurveNG is ICurve {
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount) external;

    function remove_liquidity(uint256 amount, uint256[] calldata minUAmounts) external;

    function remove_liquidity_imbalance(uint256[] calldata minUAmounts, uint256 maxBurnAmount) external;

    function calc_token_amount(uint256[] memory amounts, bool isDeposit) external view returns (uint256);
}
