// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../base/InterestVault.sol";
import "../../../../common/ProxyExtension.sol";
import "../../../../libraries/types/VaultTypes.sol";
import "../../../../interfaces/internal/access/IIngress.sol";
import "../../../../interfaces/internal/vault/extensions/groomable/IGroomableVault.sol";

/**
 * @title GroomableVaultV1
 * @dev Proxy forwarding groomable processes to GroomableManagerV1
 * @dev Also handles the configuration of the groomable parameters
 * @dev Note! The groomable vault storage should be inline with GroomableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

abstract contract GroomableVaultV1 is InterestVault, ProxyExtension, IGroomableVaultV1 {
    /// @notice Forward the execution to the GroomableManager
    function migrateLender(address newStrategy) external override onlyOwner {
        _exec(
            groomableStorage.groomableManager,
            abi.encodeWithSelector(IGroomableVaultV1.migrateLender.selector, newStrategy)
        );
    }

    /// @notice Forward the execution to the GroomableManager
    function migrateFarmDispatcher(address newFarmDispatcher) external override onlyOwner {
        _exec(
            groomableStorage.groomableManager,
            abi.encodeWithSelector(IGroomableVaultV1.migrateFarmDispatcher.selector, newFarmDispatcher)
        );
    }

    /// @notice Forward the execution to the GroomableManager
    function flashLoanCallback(bytes calldata params, uint256 migrationFee) external override {
        _exec(
            groomableStorage.groomableManager,
            abi.encodeWithSelector(IFlashLoanCallback.flashLoanCallback.selector, params, migrationFee)
        );
    }

    /// @notice Forward the execution to the GroomableManager
    function rebalance() external override nonReentrant {
        IIngress(ingressControl).validateRebalance(msg.sender);
        _updateInterest();

        _exec(groomableStorage.groomableManager, abi.encodeWithSelector(IGroomableVaultV1.rebalance.selector));
    }

    //// @notice Set the grooming configuration
    //// @param config Struct with params
    function setGroomableConfig(VaultTypes.GroomableConfig memory config) external override onlyOwner {
        if (config.maxMigrationFeePercentage > 1e18) {
            // 1e18 represents a 100%. maxMigrationFeePercentage is in percentage
            revert GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE();
        }

        groomableStorage = config;
    }

    //// @notice Return groomable config
    function getGroomableConfig() external view override returns (address, address, uint256) {
        return (
            groomableStorage.groomableManager,
            groomableStorage.flashLoanStrategy,
            groomableStorage.maxMigrationFeePercentage
        );
    }
}
