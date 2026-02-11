// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./GenericVault.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";

contract MorphoHyperithmUSDC is GenericVault {
    function _setUp() internal override {
        vm.rollFork(23593860);

        GenericVault._setUp(Constants.morpho_Vault_Hyperithm_USDC);
    }
}
