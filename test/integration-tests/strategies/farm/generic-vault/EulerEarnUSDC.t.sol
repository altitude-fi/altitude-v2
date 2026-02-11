// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./GenericVault.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";

contract EulerEarnHyperithmUSDC is GenericVault {
    function _setUp() internal override {
        vm.rollFork(23593860);

        GenericVault._setUp(Constants.euler_earn_Hyperithm_USDC);
    }
}
