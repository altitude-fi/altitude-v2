// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../libraries/uniswap-v3/OracleLibrary.sol";

contract TestUniswapV3OracleLibrary {
    constructor() {}

    /**
     * @notice Cover all revert cases for OracleLibrary.consult
     * @param pool first token
     * @param secondsAgo second token
     */
    function consult(address pool, uint32 secondsAgo) external view {
        OracleLibrary.consult(pool, secondsAgo);
    }
}
