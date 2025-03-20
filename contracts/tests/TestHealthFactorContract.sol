// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title TestHealthFactorContract
 * @dev Contarct for testing HealthFactorCalculator library (test ONLY purpose)
 * @author Altitude Labs
 **/

import "../libraries/utils/HealthFactorCalculator.sol";
import "../interfaces/internal/strategy/lending/ILenderStrategy.sol";

contract TestHealthFactorContract {
    function availableBorrow(
        address strategy,
        uint256 threshold,
        uint256 supplyBalance,
        uint256 debtBalance,
        address supplyAsset,
        address borrowAsset
    ) external view returns (uint256) {
        uint256 totalSuppliedInBase = ILenderStrategy(strategy).convertToBase(supplyBalance, supplyAsset, borrowAsset);

        return HealthFactorCalculator.availableBorrow(threshold, totalSuppliedInBase, debtBalance);
    }

    function healthFactor(
        address strategy,
        uint256 threshold,
        uint256 supplyBalance,
        uint256 debtBalance,
        address supplyAsset,
        address borrowAsset
    ) external view returns (uint256) {
        uint256 totalSuppliedInBase = ILenderStrategy(strategy).convertToBase(supplyBalance, supplyAsset, borrowAsset);

        return HealthFactorCalculator.healthFactor(threshold, totalSuppliedInBase, debtBalance);
    }

    function isPositionHealthy(
        address strategy,
        uint256 threshold,
        uint256 supplyBalance,
        uint256 debtBalance,
        address supplyAsset,
        address borrowAsset
    ) external view returns (bool) {
        return
            HealthFactorCalculator.isPositionHealthy(
                strategy,
                supplyAsset,
                borrowAsset,
                threshold,
                supplyBalance,
                debtBalance
            );
    }
}
