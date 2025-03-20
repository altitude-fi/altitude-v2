// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./VaultStorage.sol";
import "../../../interfaces/internal/vault/IInterestVault.sol";
import "../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";

abstract contract InterestVault is VaultStorage, IInterestVault {
    function _updateInterest() internal {
        if (ILenderStrategy(activeLenderStrategy).hasSupplyLoss()) {
            revert IN_V1_SUPPLY_LOSS_SNAPSHOT_NEEDED();
        }

        supplyToken.snapshot();
        debtToken.snapshot();

        ILenderStrategy(activeLenderStrategy).updatePrincipal();
    }
}
