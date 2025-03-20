// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../base/InterestVault.sol";
import "../../../../common/ProxyExtension.sol";

import "../../../../libraries/types/VaultTypes.sol";
import "../../../../libraries/utils/HealthFactorCalculator.sol";
import "../../../../interfaces/internal/access/IIngress.sol";
import "../../../../interfaces/internal/vault/extensions/IVaultExtensions.sol";
import "../../../../interfaces/internal/vault/extensions/liquidatable/ILiquidatableVault.sol";

/**
 * @title LiquidatableVault
 * @dev Proxy forwarding, liquidation processed by LiquidatableManager
 * @dev Also handles the configuration of the liquidation parameters
 * @dev Note! The LiquidatableVault storage should be inline with LiquidatableManager
 * @dev Note! because of the proxy standard(delegateCall)
 * @author Altitude Labs
 **/

abstract contract LiquidatableVaultV1 is InterestVault, ProxyExtension, ILiquidatableVaultV1 {
    /// @notice Forward execution to the LiquidatableManager
    /// @param usersForLiquidation User addresses
    /// @param repayAmountLimit Max amount the liquidator wants to pay
    function liquidateUsers(address[] calldata usersForLiquidation, uint256 repayAmountLimit)
        external
        override
        nonReentrant
    {
        IIngress(ingressControl).validateLiquidateUsers(msg.sender);

        // We need to update position because the liquidation will change the users' balances.
        // Note: If the batch is too big we may hit the block gas limit.
        IVaultExtensions(address(this)).updatePositions(usersForLiquidation);
        IVaultExtensions(address(this)).updatePosition(msg.sender);

        _exec(
            liquidatableStorage.liquidatableManager,
            abi.encodeWithSelector(ILiquidatableManager.liquidateUsers.selector, usersForLiquidation, repayAmountLimit)
        );
    }

    /// @notice Checks if a user should be liquidated, without accounting for pending harvests
    /// @param userAddress User address to check
    /// @dev Function used to simplify external integration (e.g. liquidations)
    function isUserForLiquidation(address userAddress) external view override returns (bool isUserForLiquidator) {
        return
            !HealthFactorCalculator.isPositionHealthy(
                activeLenderStrategy,
                supplyUnderlying,
                borrowUnderlying,
                liquidationThreshold,
                supplyToken.balanceOf(userAddress),
                debtToken.balanceOf(userAddress)
            );
    }

    //// @notice Set liquidation parameters
    //// @param config Struct with params
    function setLiquidationConfig(VaultTypes.LiquidatableConfig memory config) external onlyOwner {
        if (config.liquidationBonus > 1e18) {
            // 1e18 represents a 100%. liquidationBonus is in percentage
            revert LQ_V1_MAX_BONUS_OUT_OF_RANGE();
        }

        if (config.maxPositionLiquidation > 1e18) {
            // 1e18 represents a 100%. maxPositionLiquidation is in percentage
            revert LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE();
        }

        liquidatableStorage = config;
    }

    //// @notice Return liquidation config
    function getLiquidationConfig()
        external
        view
        override
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            liquidatableStorage.liquidatableManager,
            liquidatableStorage.maxPositionLiquidation,
            liquidatableStorage.liquidationBonus,
            liquidatableStorage.minUsersToLiquidate,
            liquidatableStorage.minRepayAmount
        );
    }
}
