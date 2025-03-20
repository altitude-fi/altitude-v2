// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IHarvestableManager {
    event Harvested(
        uint256 harvestId,
        uint256 distributableProfit,
        uint256 vaultLoss,
        uint256 uncommittedLossPerc,
        uint256 claimableLossPerc
    );

    event ClaimedRewards(address indexed account, uint256 amountClaimed, uint256 debtRepayed);

    event InjectedBorrowAssets(uint256 amount);

    // Harvest Errors
    error HM_V1_BLOCK_ERROR();
    error HM_V1_INVALID_INJECT_AMOUNT();
    error HM_V1_HARVEST_ERROR();
    error HM_V1_PRICE_TOO_LOW();
    error HM_V1_INVALID_COMMIT();
    error HM_V1_CLAIM_REWARDS_ZERO();
    error HV_V1_HM_NO_ACTIVE_ASSETS();
    error HV_V1_RESERVE_FACTOR_OUT_OF_RANGE();
    error HM_V1_TOO_BIG_FARM_LOSS(uint256 farmRewardsLoss);
    error HM_V1_FARM_MODE_RESERVE_NOT_ENOUGH();

    function harvest(uint256 price) external;

    function withdrawReserve(address receiver, uint256 amount) external returns (uint256);

    function claimRewards(uint256 amountRequested) external returns (uint256);

    function injectBorrowAssets(uint256 amount) external;
}
