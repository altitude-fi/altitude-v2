// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IAaveStrategy {
    event ClaimRewards();
    event Redeem(uint256 aTokensRedeemed);

    // Strategy Aave Errors
    error SA_IN_COOLDOWN_PERIOD();
    error SA_REDEEM_NOT_ALLOWED();
    error SA_ZERO_REWARDS_TO_CLAIM();
    error SA_ZERO_REWARDS_TO_REDEEM();

    function canClaim() external view returns (bool);

    function claimRewards() external;

    function canRedeem() external view returns (bool);

    function redeem() external;
}
