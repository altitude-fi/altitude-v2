// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IConfig} from "./IConfig.sol";

abstract contract Config is IConfig {
    address public GRAND_ADMIN;

    function initConfig(address grandAdmin) public {
        GRAND_ADMIN = grandAdmin;
    }

    function _priceSource() internal virtual returns (address);

    function _farmStrategies(address farmDispatcher) internal virtual returns (address[] memory);

    function _swapStrategy() internal virtual returns (address);

    function _flashLoanStrategy() internal virtual returns (address);

    function _lenderStrategy(address vaultAddress, address farmDispatcher) internal virtual returns (address);
}
