// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./../../base/VaultStorage.sol";
import "../../../../interfaces/internal/vault/extensions/configurable/IConfigurableVault.sol";

/**
 * @title ConfigurableManager
 * @dev Contract for configuring vault properties
 * @author Altitude Labs
 **/

contract ConfigurableManager is VaultStorage, IConfigurableVaultV1 {
    /// @notice Set Vault Configuration
    /// @param confugrableManager_ Contract responsible for configuraion logic
    /// @param swapStrategy_ Contract to process swaps in case of vault being liquidated
    /// @param borrowVerifier_ Contract to validate borrowOnBehalfOf signatures
    /// @param withdrawFeeFactor_ Applicable withdraw fee
    /// @param withdrawFeePeriod_ Applicable withdraw fee period
    function setConfig(
        address confugrableManager_,
        address swapStrategy_,
        address ingressControl_,
        address borrowVerifier_,
        uint256 withdrawFeeFactor_,
        uint256 withdrawFeePeriod_
    ) external override {
        if (withdrawFeeFactor_ > 1e18) {
            // 1e18 represents a 100%. withdrawFeeFactor_ is in percentage
            revert VCONF_V1_WITHDRAW_FEE_FACTOR_OUT_OF_RANGE();
        }

        configurableManager = confugrableManager_;
        swapStrategy = swapStrategy_;
        ingressControl = ingressControl_;
        borrowVerifier = IBorrowVerifier(borrowVerifier_);
        withdrawFeeFactor = withdrawFeeFactor_;
        withdrawFeePeriod = withdrawFeePeriod_;
    }

    /// @notice Set Vault Borrow Limits
    /// @param supplyThreshold_ Percentage of a users supply value that can be borrowed
    /// @param liquidationThreshold_ Percentage value of borrows to supply above which the user can be liquidated
    /// @param targetThreshold_ Percentage value the vault aims to rebalance to in support of yield farming
    function setBorrowLimits(
        uint256 supplyThreshold_,
        uint256 liquidationThreshold_,
        uint256 targetThreshold_
    ) external virtual override {
        if (
            supplyThreshold_ > 1e18 || supplyThreshold_ > liquidationThreshold_ // 1e18 represents a 100%. supplyThreshold_ is in percentage
        ) {
            revert VCONF_V1_SUPPLY_THRESHOLD_OUT_OF_RANGE();
        }

        if (
            targetThreshold_ > 1e18 || targetThreshold_ > liquidationThreshold_ // 1e18 represents a 100%. targetThreshold_ is in percentage
        ) {
            revert VCONF_V1_TARGET_THRESHOLD_OUT_OF_RANGE();
        }

        if (liquidationThreshold_ > 1e18) {
            // 1e18 represents a 100%. liquidationThreshold_ is in percentage
            revert VCONF_V1_LIQUIDATION_THRESHOLD_OUT_OF_RANGE();
        }

        supplyThreshold = supplyThreshold_;
        liquidationThreshold = liquidationThreshold_;
        targetThreshold = targetThreshold_;
    }

    /// @notice Reduce the target threshold in case of emergency
    /// @param targetThreshold_ Percentage value the vault aims to rebalance to in support of yield farming
    function reduceTargetThreshold(uint256 targetThreshold_) external virtual override {
        // The target threshold is only to be reduced
        if (targetThreshold_ >= targetThreshold) {
            revert VCONF_V1_TARGET_THRESHOLD_NOT_REDUCED();
        }

        targetThreshold = targetThreshold_;
    }

    /// @notice User grants or disables other users to interact on their behalf
    /// @notice This gives control to the user to allow any interactions that may affect their reward earnings
    /// @notice Functions limited are `deposit`, `repay` and receiving (`transfer`)
    /// @dev In future functions limited may be updated with `disableOnBehalfValidation()`
    /// @param allowees list of addresses user is allowing to act on their behalf
    /// @param toAllow flag - true/false to be applied to all listed addresses
    function allowOnBehalf(address[] memory allowees, bool toAllow) external override {
        uint256 alloweesCount = allowees.length;
        for (uint256 i; i < alloweesCount; ) {
            allowOnBehalfList[msg.sender][allowees[i]] = toAllow;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Disable onBehalf validation for the provided functions
    /// @dev This may only be applied if an upgrade removes risks related to each function
    /// @param functions list of functions to disable the validation for
    function disableOnBehalfValidation(bytes4[] memory functions, bool toDisable) external override {
        uint256 functionsNumber = functions.length;
        for (uint256 i; i < functionsNumber; ) {
            onBehalfFunctions[functions[i]] = toDisable;
            unchecked {
                ++i;
            }
        }
    }
}
