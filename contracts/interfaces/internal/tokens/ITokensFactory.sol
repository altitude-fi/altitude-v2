// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface ITokensFactory {
    error TF_ZERO_ADDRESS();
    error TF_ONLY_REGISTRY();

    event UpdateProxyAdmin(address newProxyAdmin);
    event SetRegistry(address newRegistryAddress);
    event SetSupplyTokenImplementation(address implementation);
    event SetDebtTokenImplementation(address implementation);

    function registry() external view returns (address);

    function debtTokenImplementation() external view returns (address);

    function supplyTokenImplementation() external view returns (address);

    function proxyAdmin() external view returns (address);

    function setRegistry(address newRegistryAddress) external;

    function setSupplyTokenImplementation(address newSupplyTokenImplentation) external;

    function setDebtTokenImplementation(address newDebtTokenImplentation) external;

    function setProxyAdmin(address newProxyAdmin) external;

    function createPair(
        address vault,
        address supplyAsset,
        address borrowAsset,
        uint256 supplyUnits,
        uint256 borrowUnits,
        address lenderStrategy
    ) external returns (address supplyTokenAddress, address debtTokenAddress);
}
