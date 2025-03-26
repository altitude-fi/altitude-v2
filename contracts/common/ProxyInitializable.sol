// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

/**
 * @title ProxyInitializable
 * @dev ProxyInitializable contract providing upgradability
 * @author Altitude Labs
 **/

contract ProxyInitializable is Proxy, ERC1967Upgrade {
    /// @notice Used as a constructor due to create2 with no params
    function initialize(address _admin, address _logic, bytes memory _data) external {
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));

        require(_implementation() == address(0) && _logic != address(0), "ALREADY_INITIALIZED");

        _upgradeToAndCall(_logic, _data, false);
        _changeAdmin(_admin);
    }

    /// @notice Returns the current implementation address.
    function _implementation() internal view virtual override returns (address impl) {
        return ERC1967Upgrade._getImplementation();
    }

    /// @notice Set the new implementation of a vault
    /// @param newImplementation Address of the implementation contract
    function upgradeTo(address newImplementation) external {
        require(_getAdmin() == msg.sender, "NOT_PROXY_ADMIN");
        require(newImplementation != address(0), "ZERO_IMPLEMENTATION_NOT_ALLOWED");

        _upgradeTo(newImplementation);
    }

    /// @notice Transfers admin rights
    /// @param newAdmin Address of the new proxy adminsitrator
    function changeAdmin(address newAdmin) external {
        require(_getAdmin() == msg.sender, "NOT_PROXY_ADMIN");
        _changeAdmin(newAdmin);
    }

    /// @notice Returns the admin
    function getAdmin() external view returns (address) {
        return _getAdmin();
    }
}
