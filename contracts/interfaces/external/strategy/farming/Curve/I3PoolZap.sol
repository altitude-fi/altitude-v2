// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface I3PoolZap {
    function add_liquidity(
        address pool,
        uint256[4] calldata depositAmounts,
        uint256 minMintAmount
    ) external returns (uint256);

    function remove_liquidity_one_coin(
        address pool,
        uint256 burnAmount,
        int128 i,
        uint256 minAmount
    ) external returns (uint256);

    function calc_withdraw_one_coin(
        address pool,
        uint256 tokenAmount,
        int128 i
    ) external view returns (uint256);

    function remove_liquidity(
        address pool,
        uint256 burnAmount,
        uint256[4] calldata minAmounts
    ) external returns (uint256[4] memory);

    function calc_token_amount(
        address pool,
        uint256[4] calldata amounts,
        bool isDeposit
    ) external view returns (uint256);
}
