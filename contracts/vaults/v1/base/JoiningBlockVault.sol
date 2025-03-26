// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./VaultStorage.sol";
import "../../../interfaces/internal/strategy/lending/ILenderStrategy.sol";

/**
 * @title JoiningBlock
 * @dev Contract to be reused in LiquidatableManager and HarvestableManager
 * @author Altitude Labs
 **/

contract JoiningBlockVault is VaultStorage {
    /// @notice If the user's active assets are positive, move the joining block to the current block
    /// @param account User address
    function _updateEarningsRatio(address account) internal {
        uint256 price = ILenderStrategy(activeLenderStrategy).getInBase(
            supplyToken.underlying(),
            debtToken.underlying()
        );
        uint256 userSupplyInBase = ((supplyToken.balanceOf(account) * price) / 10 ** supplyToken.decimals());

        uint256 activeAssets = ((userSupplyInBase * liquidationThreshold) / 1e18) +
            harvestStorage.userHarvest[account].claimableEarnings;

        if (activeAssets >= debtToken.balanceOf(account)) {
            harvestStorage.userHarvest[account].harvestJoiningBlock = block.number;
        }
    }
}
