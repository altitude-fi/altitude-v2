// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;
import "./ICurve.sol";

interface ICurve4 is ICurve {
    function price_oracle(uint256 index) external view returns (uint256 price);

    function add_liquidity(uint256[4] calldata amounts, uint256 minMintAmount) external;

    function remove_liquidity(uint256 amount, uint256[4] calldata minUAmounts) external;

    function remove_liquidity_imbalance(uint256[4] calldata minUAmounts, uint256 maxBurnAmount) external;

    function underlying_coins() external returns (address[4] memory);

    function calc_token_amount(uint256[4] memory amounts, bool isDeposit) external view returns (uint256);
}
