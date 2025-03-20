// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IConfigurableVaultV1 {
    // Configurable vault Errors
    error VCONF_V1_TARGET_THRESHOLD_NOT_REDUCED();
    error VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE();
    error VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE();
    error VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE();
    error VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE();

    function setConfig(
        address confugrableManager_,
        address swapStrategy_,
        address ingressControl_,
        address borrowVerifier_,
        uint256 withdrawFeeFactor_,
        uint256 withdrawFeePeriod_
    ) external;

    function setBorrowLimits(
        uint256 supplyThreshold_,
        uint256 liquidationThreshold_,
        uint256 targetThreshold_
    ) external;

    function reduceTargetThreshold(uint256 targetThreshold_) external;

    function allowOnBehalf(address[] memory allowees, bool toAllow) external;

    function disableOnBehalfValidation(bytes4[] memory functions, bool toDisable) external;
}
