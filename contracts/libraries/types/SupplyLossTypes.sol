// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title SupplyLossTypes
 * @dev Input parameters for not having "Stack too deep"
 * @author Altitude Labs
 **/

library SupplyLossTypes {
    // @notice track data for a supply loss
    struct SupplyLoss {
        uint256 supplyLossAtSnapshot; // total reduction of supply, less fees
        uint256 supplyLossProfit; // interest earned on supply (if any, zero if supplyLossAtSnapshot > 0)
        uint256 borrowLossAtSnapshot; // total reduction of borrows
        uint256 supplyBalanceAtSnapshot; // vault total supplied at snapshot
        uint256 borrowBalanceAtSnapshot; // vault total user borrows at snapshot
        uint256 fee; // combination of liquidation penalty, slippage and deposit fees
        uint256 withdrawShortage; // vault farm balance less farm withdrawal amount (if any)
    }

    // @notice supply loss storage
    struct SupplyLossStorage {
        SupplyLoss[] supplyLosses; // array of all supply loss snapshots
    }
}
