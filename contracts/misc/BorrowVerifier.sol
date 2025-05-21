// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "../interfaces/internal/misc/IBorrowVerifier.sol";

/**
 * @title BorrowVerifier
 * @notice Verify borrow parameters against a signature
 * @author Altitude Labs
 **/

contract BorrowVerifier is IBorrowVerifier, EIP712 {
    mapping(address => uint256) public override nonce;
    address public vault;

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert BV_ONLY_VAULT();
        }
        _;
    }

    constructor(address _vault) EIP712("AltitudeBorrowVerifier", "1") {
        if (_vault == address(0)) {
            revert BV_INVALID_VAULT();
        }
        vault = _vault;
    }

    /// @notice Verifies the borrow parameters against the signature and burns a nonce
    /// @param amount The amount to borrow
    /// @param onBehalfOf The address incurring the debt
    /// @param receiver The address receiving the borrowed amount
    /// @param deadline Expiry date of the signature in Unix time
    /// @param signature onBehalfOf's signature for these parameters
    function verifyAndBurnNonce(
        uint256 amount,
        address onBehalfOf,
        address receiver,
        uint256 deadline,
        bytes calldata signature
    ) external override onlyVault {
        if (block.timestamp > deadline) {
            revert BV_DEADLINE_PASSED();
        }

        address signer = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowApproval(uint256 amount,address onBehalfOf,address receiver,uint256 deadline,uint256 nonce)"
                        ),
                        amount,
                        onBehalfOf,
                        receiver,
                        deadline,
                        nonce[onBehalfOf]
                    )
                )
            ),
            signature
        );

        if (signer != onBehalfOf) {
            revert BV_INVALID_SIGNATURE();
        }

        nonce[signer]++;
    }
}
