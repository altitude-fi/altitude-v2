// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title RolesGranter
 * @notice Helpers
 * @author Altitude Labs
 **/

import "@openzeppelin/contracts/access/IAccessControl.sol";

import {Roles} from "../../contracts/common/Roles.sol";
import {IConfig} from "./IConfig.sol";

library RolesGranter {
    function _grantRoles(address accessContract, IConfig config) internal {
        // Grant roles
        for (uint256 i = 0; i < config.ALPHA_ROLE_LENGTH(); i++) {
            IAccessControl(accessContract).grantRole(Roles.ALPHA, config.ALPHA_ROLE(i));
        }
        for (uint256 i = 0; i < config.BETA_ROLE_LENGTH(); i++) {
            IAccessControl(accessContract).grantRole(Roles.BETA, config.BETA_ROLE(i));
        }
        for (uint256 i = 0; i < config.GAMMA_ROLE_LENGTH(); i++) {
            IAccessControl(accessContract).grantRole(Roles.GAMMA, config.GAMMA_ROLE(i));
        }
    }
}
