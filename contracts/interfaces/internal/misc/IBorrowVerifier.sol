// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IBorrowVerifier {
    // Borrow Verifier Errors
    error BV_DEADLINE_PASSED();
    error BV_INVALID_SIGNATURE();
    error BV_ONLY_VAULT();
    error BV_INVALID_VAULT();

    function nonce(address) external returns (uint256);

    function verifyAndBurnNonce(
        uint256 amount,
        address onBehalfOf,
        address receiver,
        uint256 deadline,
        bytes calldata signature
    ) external;
}
