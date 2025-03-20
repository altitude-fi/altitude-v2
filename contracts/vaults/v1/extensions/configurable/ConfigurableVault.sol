// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../base/VaultStorage.sol";
import "../../../../common/ProxyExtension.sol";
import "../../../../interfaces/internal/vault/extensions/configurable/IConfigurableVault.sol";

/**
 * @title ConfigurableManager
 * @dev Contract for configuring vault properties
 * @author Altitude Labs
 **/

abstract contract ConfigurableVaultV1 is VaultStorage, ProxyExtension, IConfigurableVaultV1 {
    /// @notice Forwards to configurable manager
    function setConfig(
        address configurableManager_,
        address swapStrategy_,
        address ingressControl_,
        address borrowVerifier_,
        uint256 withdrawFeeFactor_,
        uint256 withdrawFeePeriod_
    ) external override onlyOwner {
        _exec(
            configurableManager,
            abi.encodeWithSelector(
                IConfigurableVaultV1.setConfig.selector,
                configurableManager_,
                swapStrategy_,
                ingressControl_,
                borrowVerifier_,
                withdrawFeeFactor_,
                withdrawFeePeriod_
            )
        );
    }

    /// @notice Forwards to configurable manager
    function setBorrowLimits(
        uint256 supplyThreshold_,
        uint256 liquidationThreshold_,
        uint256 targetThreshold_
    ) external virtual override onlyOwner {
        _exec(
            configurableManager,
            abi.encodeWithSelector(
                IConfigurableVaultV1.setBorrowLimits.selector,
                supplyThreshold_,
                liquidationThreshold_,
                targetThreshold_
            )
        );
    }

    /// @notice Forwards to configurable manager
    function reduceTargetThreshold(uint256 targetThreshold_) external virtual override onlyOwner {
        _exec(
            configurableManager,
            abi.encodeWithSelector(IConfigurableVaultV1.reduceTargetThreshold.selector, targetThreshold_)
        );
    }

    /// @notice Forwards to configurable manager
    function allowOnBehalf(address[] memory allowees, bool toAllow) external override {
        _exec(
            configurableManager,
            abi.encodeWithSelector(IConfigurableVaultV1.allowOnBehalf.selector, allowees, toAllow)
        );
    }

    /// @notice Forwards to configurable manager
    function disableOnBehalfValidation(bytes4[] memory functions, bool toDisable) external override onlyOwner {
        _exec(
            configurableManager,
            abi.encodeWithSelector(IConfigurableVaultV1.disableOnBehalfValidation.selector, functions, toDisable)
        );
    }
}
