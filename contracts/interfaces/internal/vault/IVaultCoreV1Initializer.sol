// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../../../libraries/types/VaultTypes.sol";

/**
 * @author Altitude Protocol
 **/

interface IVaultCoreV1Initializer {
    event SetTokens(address supplyInterestToken, address borrowInterestToken);

    // Config Errors
    error VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE();
    error VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE();
    error VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE();
    error VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE();

    // Groomable Errors
    error GR_V1_MIGRATION_PERCENTAGE_OUT_OF_RANGE();

    // Liquidation Errors
    error LQ_V1_MAX_BONUS_OUT_OF_RANGE();
    error LQ_V1_MAX_POSITION_LIQUIDATION_OUT_OF_RANGE();

    // Harvest Errors
    error HV_V1_RESERVE_FACTOR_OUT_OF_RANGE();

    function initialize(address contractOwner, VaultTypes.VaultData memory vaultData) external;

    function setTokens(address supplyInterestToken, address borrowInterestToken) external;
}
