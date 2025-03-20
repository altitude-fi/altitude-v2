// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface ICurveRouter {
    function get_dx(
        address[11] memory _route,
        uint256[5][5] memory _swap_params,
        uint256 _out_amount,
        address[5] memory _pools
    ) external view returns (uint256 amountOut);

    function get_dy(
        address[11] memory _route,
        uint256[5][5] memory _swap_params,
        uint256 _in_amount,
        address[5] memory _pools
    ) external view returns (uint256 amountIn);

    function exchange(
        address[11] memory _route,
        uint256[5][5] memory _swap_params,
        uint256 _amount,
        uint256 _expected,
        address[5] memory _pools,
        address recipient
    ) external returns (uint256 amoutOut);
}
