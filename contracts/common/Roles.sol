// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title Roles definition
 * @dev Library for roles
 * @author Altitude Labs
 **/

library Roles {
    bytes32 internal constant ALPHA = keccak256("ALPHA");
    bytes32 internal constant BETA = keccak256("BETA");
    bytes32 internal constant GAMMA = keccak256("GAMMA");
}
