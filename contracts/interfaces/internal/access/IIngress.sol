// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title Ingress interface
 * @author Altitude Labs
 **/

interface IIngress is IAccessControl {
    // Type of transactions the rate limit can apply to
    enum RateLimitType {
        Withdraw,
        Borrow,
        Claim
    }

    event UpdateRateLimit(uint256[3] _rateLimitPeriod, uint256[3] _rateLimitAmount);
    event UpdateSanctionedList(address[] sanctionedList, bool toSanction);
    event UpdateDepositLimits(uint256 userMinDepositLimit, uint256 userMaxDepositLimit, uint256 vaultDepositLimit);
    event SetProtocolPause(bool toPause);
    event SetFunctionsState(bytes4[] functions, bool toPause);

    // Ingress Control Errors
    error IN_V1_FUNCTION_PAUSED();
    error IN_V1_PROTOCOL_PAUSED();
    error IN_V1_CLAIM_RATE_LIMIT();
    error IN_V1_BORROW_RATE_LIMIT();
    error IN_V1_WITHDRAW_RATE_LIMIT();
    error IN_V1_USER_DEPOSIT_MINIMUM_UNMET();
    error IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
    error IN_V1_USER_DEPOSIT_LIMIT_EXCEEDED();
    error IN_V1_VAULT_DEPOSIT_LIMIT_EXCEEDED();
    error IN_ACCOUNT_CAN_NOT_CALL_THIS_FUNCTION();

    function sanctioned(address) external view returns (bool);

    function userMinDepositLimit() external view returns (uint256);

    function userMaxDepositLimit() external view returns (uint256);

    function vaultDepositLimit() external view returns (uint256);

    function pause() external view returns (bool);

    function setSanctioned(address[] memory _sanctioned, bool toSanction) external;

    function isFunctionDisabled(bytes4) external view returns (bool);

    function setRateLimit(uint256[3] memory _rateLimitPeriod, uint256[3] memory _rateLimitAmount) external;

    function setDepositLimits(
        uint256 _userMinDepositLimit,
        uint256 _userMaxDepositLimit,
        uint256 _vaultDepositLimit
    ) external;

    function setProtocolPause(bool toPause) external;

    function setFunctionsPause(bytes4[] memory functions, bool toPause) external;

    function validateDeposit(address depositor, address recipient, uint256 amount) external view;

    function validateWithdraw(address withdrawer, address recipient, uint256 amount) external;

    function validateBorrow(address borrower, address recipient, uint256 amount) external;

    function validateRepay(address repayer, address recipient) external view;

    function validateTransfer(address from, address to) external view;

    function validateClaimRewards(address claimer, uint256 amount) external;

    function validateCommit() external view;

    function validateRebalance(address sender) external view;

    function validateLiquidateUsers(address liquidator) external view;

    function validateSnapshotSupplyLoss(address sender) external view;
}
