// SPDX-License-Identifier: AGPL-3.0.0
pragma solidity 0.8.28;

/**
 * @title LendingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 * - Acting also as factory of proxies and admin of those, so with right to change its implementations
 * - Owned by the Aave Governance
 * @author Aave
 **/

interface IAaveLendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);

    function getPriceOracle() external view returns (address);
}
