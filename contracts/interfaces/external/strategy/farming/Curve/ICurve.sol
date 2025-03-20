// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

interface ICurve {
    function remove_liquidity_one_coin(
        uint256 token_amount,
        int128 i,
        uint256 min_uamount
    ) external;

    function calc_withdraw_one_coin(uint256 tokenAmount, int128 i) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function curve() external view returns (address);

    function balances(address) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function fee() external view returns (uint256);

    function admin_fee() external view returns (uint256);
}
