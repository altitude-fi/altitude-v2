// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../../base/VaultStorage.sol";
import "../../../../../common/ProxyExtension.sol";
import "../../../../../interfaces/internal/access/IIngress.sol";
import "../../../../../interfaces/internal/vault/extensions/supply-loss/ISupplyLossVault.sol";

/**
 * @title SupplyLossVaultV1
 * @dev Proxy forwarding, supply loss snapshot processed by SupplyLossManager
 * @dev Note! The SupplyLossVaultV1 storage should be inline with SupplyLossVaultV1
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

abstract contract SupplyLossVaultV1 is VaultStorage, ProxyExtension, ISupplyLossVaultV1 {
    /// @notice Forward execution to the SupplyLossManager
    function snapshotSupplyLoss() external override nonReentrant {
        IIngress(ingressControl).validateSnapshotSupplyLoss(msg.sender);

        _exec(snapshotManager, abi.encodeWithSelector(ISupplyLossManager.snapshotSupplyLoss.selector));

        // Pause protocol to allow the cause of the supplyLoss to be analysed
        IIngress(ingressControl).setProtocolPause(true);
    }

    /// @notice Returns a supply loss snapshot for a given id
    function getSupplyLossSnapshot(uint256 id) external view override returns (SupplyLossTypes.SupplyLoss memory) {
        return supplyLossStorage.supplyLosses[id];
    }
}
