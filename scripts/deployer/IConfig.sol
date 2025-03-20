// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IConfig {
    function isERC20Vault() external view returns (bool);

    function GRAND_ADMIN() external view returns (address);

    function UPGRADABILITY_EXECUTOR() external view returns (address);

    function RESERVE_RECEIVER() external view returns (address);

    function USER_MIN_DEPOSIT_LIMIT() external view returns (uint256);

    function USER_MAX_DEPOSIT_LIMIT() external view returns (uint256);

    function VAULT_MAX_DEPOSIT_LIMIT() external view returns (uint256);

    function WITHDRAW_RATE_LIMIT() external view returns (uint256);

    function WITHDRAW_RATE_AMOUNT() external view returns (uint256);

    function BORROW_RATE_LIMIT() external view returns (uint256);

    function BORROW_RATE_AMOUNT() external view returns (uint256);

    function CLAIM_RATE_LIMIT() external view returns (uint256);

    function CLAIM_RATE_AMOUNT() external view returns (uint256);

    function WITHDRAW_FEE_FACTOR() external view returns (uint256);

    function WITHDRAW_FEE_PERIOD() external view returns (uint256);

    function SUPPLY_THRESHOLD() external view returns (uint256);

    function LIQUIDATION_THRESHOLD() external view returns (uint256);

    function TARGET_THRESHOLD() external view returns (uint256);

    function MAX_POSITION_LIQUIDATION() external view returns (uint256);

    function LIQUIDATION_BONUS() external view returns (uint256);

    function MIN_USERS_TO_LIQUIDATE() external view returns (uint256);

    function MIN_REPAY_AMOUNT() external view returns (uint256);

    function MAX_MIGRATION_FEE_PERCENTAGE() external view returns (uint256);

    function RESERVE_FACTOR() external view returns (uint256);

    function SUPPLY_MATH_UNITS() external view returns (uint256);

    function BORROW_MATH_UNITS() external view returns (uint256);

    function REBALANCE_INCENTIVE_REWARD_TOKEN() external view returns (address);

    function REBALANCE_MIN_DEVIATION() external view returns (uint256);

    function REBALANCE_MAX_DEVIATION() external view returns (uint256);

    function ALPHA_ROLE_LENGTH() external view returns (uint256);

    function ALPHA_ROLE(uint256 index) external view returns (address);

    function BETA_ROLE_LENGTH() external view returns (uint256);

    function BETA_ROLE(uint256 index) external view returns (address);

    function GAMMA_ROLE_LENGTH() external view returns (uint256);

    function GAMMA_ROLE(uint256 index) external view returns (address);

    function BUFFER_SIZE() external view returns (uint256);

    function CAPS(uint256 index) external view returns (uint256);

    function supplyAsset() external returns (address);

    function borrowAsset() external returns (address);
}
