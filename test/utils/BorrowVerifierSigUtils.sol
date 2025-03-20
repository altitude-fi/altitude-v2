pragma solidity 0.8.28;

import {Vm} from "forge-std/Test.sol";

library BorrowVerifierSigUtils {
    // keccak256("BorrowApproval(uint256 amount,address onBehalfOf,address receiver,uint256 deadline,uint256 nonce)");
    bytes32 public constant BORROW_APPROVAL_TYPEHASH =
        0xa1624e7e95a39a76cb8ed7fd4f86cdbd2e8f7f78170cc2eaf1a7873b9bfb8686;

    function approveBorrow(
        Vm vm,
        address borrowVerifier,
        uint256 borrowAmount
    )
        public
        view
        returns (
            address user,
            address user2,
            bytes memory signature
        )
    {
        uint256 userPrivateKey = 0xA11CE;
        uint256 user2PrivateKey = 0xB0B;

        user = vm.addr(userPrivateKey);
        user2 = vm.addr(user2PrivateKey);

        bytes32 DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("AltitudeBorrowVerifier")),
                keccak256(bytes("1")),
                block.chainid,
                address(borrowVerifier)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            userPrivateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(BORROW_APPROVAL_TYPEHASH, borrowAmount, user, user2, 1 days, 0))
                )
            )
        );

        signature = abi.encodePacked(r, s, v);
    }
}
