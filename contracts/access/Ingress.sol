// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "../common/Roles.sol";
import "../interfaces/internal/access/IIngress.sol";
import "../interfaces/internal/vault/IVaultCore.sol";
import "../interfaces/internal/strategy/lending/ILenderStrategy.sol";

/**
 * @title Ingress
 * @dev Implementation of access restrictions for the vault functions
 * @author Altitude Labs
 **/

contract Ingress is AccessControl, IIngress {
    struct RateLimit {
        uint256 period; // Time period in blocks until the rate limit resets
        uint256 amount; // Amount allowed to be transferred in the period
        uint256 available; // Amount available to be transferred in the period
        uint256 updated; // Last block the rate limit was updated
    }

    /** @notice Addresses (not)allowed to interact with Altitude */
    mapping(address => bool) public override sanctioned;

    /// @notice Mapping with all protocol functions that have been disabled
    mapping(bytes4 => bool) public override isFunctionDisabled;

    /// @notice Mininum deposit amount required per user
    uint256 public override userMinDepositLimit;
    /// @notice Maximum deposit amount per user
    uint256 public override userMaxDepositLimit;
    /// @notice Maximum deposit amount for the vault
    uint256 public override vaultDepositLimit;

    /// @notice If the protocol has been paused
    bool public override pause;

    /// @dev {supply, borrow, claim}
    RateLimit[3] public rateLimit;

    constructor(
        address admin,
        address[] memory _sanctioned, // initial sanctioned list of addresses
        uint256 _userMinDepositLimit, // initial user min deposit limit
        uint256 _userMaxDepositLimit, // initial user max deposit limit
        uint256 _vaultDepositLimit, // initial vault deposit limit
        uint256[3] memory _rateLimitPeriod, // initial rate limit period
        uint256[3] memory _rateLimitAmount // initial rate limit amount
    ) {
        // Set the initial sanctioned values
        uint256 sanctionedListLength = _sanctioned.length;
        for (uint256 i; i < sanctionedListLength; ) {
            sanctioned[_sanctioned[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Set the initial deposit limits
        userMinDepositLimit = _userMinDepositLimit;
        userMaxDepositLimit = _userMaxDepositLimit;
        vaultDepositLimit = _vaultDepositLimit;

        for (uint256 i; i < 3; ) {
            rateLimit[i].period = _rateLimitPeriod[i];
            rateLimit[i].amount = _rateLimitAmount[i];
            rateLimit[i].available = _rateLimitAmount[i];
            unchecked {
                ++i;
            }
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Set rate limit params
    /// @param _rateLimitPeriod How many blocks is the interval
    /// @param _rateLimitAmount Amount of tokens for the interval
    function setRateLimit(
        uint256[3] memory _rateLimitPeriod,
        uint256[3] memory _rateLimitAmount
    ) external override onlyRole(Roles.BETA) {
        for (uint256 i; i < 3; ) {
            rateLimit[i].period = _rateLimitPeriod[i];
            rateLimit[i].amount = _rateLimitAmount[i];
            rateLimit[i].available = _rateLimitAmount[i];
            unchecked {
                ++i;
            }
        }

        emit UpdateRateLimit(_rateLimitPeriod, _rateLimitAmount);
    }

    /// @notice Disable/Enable access for EOAs
    /// @param _sanctioned list of sanctioned EOAs
    function setSanctioned(address[] memory _sanctioned, bool toSanction) external override onlyRole(Roles.GAMMA) {
        uint256 sanctionedListLength = _sanctioned.length;
        for (uint256 i; i < sanctionedListLength; ) {
            sanctioned[_sanctioned[i]] = toSanction;
            unchecked {
                ++i;
            }
        }

        emit UpdateSanctionedList(_sanctioned, toSanction);
    }

    /// @notice Set Deposit Limits
    /// @param _userMinDepositLimit User min allowed deposit amount
    /// @param _userMaxDepositLimit User total allowed deposit amount
    /// @param _vaultDepositLimit Vault total allowed deposit amount
    function setDepositLimits(
        uint256 _userMinDepositLimit,
        uint256 _userMaxDepositLimit,
        uint256 _vaultDepositLimit
    ) external override onlyRole(Roles.BETA) {
        userMinDepositLimit = _userMinDepositLimit;
        userMaxDepositLimit = _userMaxDepositLimit;
        vaultDepositLimit = _vaultDepositLimit;

        emit UpdateDepositLimits(_userMinDepositLimit, _userMaxDepositLimit, _vaultDepositLimit);
    }

    /// @notice Pause/Unpause protocol, limiting specific protocol interactions
    /// @param toPause The pause state of the protocol
    function setProtocolPause(bool toPause) external override onlyRole(Roles.GAMMA) {
        pause = toPause;

        emit SetProtocolPause(toPause);
    }

    /// @notice Pause/Unpause one or more specific vault functions
    /// @param functions function selectors
    /// @param toPause enable/disable pausing
    function setFunctionsPause(bytes4[] memory functions, bool toPause) external override onlyRole(Roles.GAMMA) {
        for (uint256 i; i < functions.length; ++i) {
            isFunctionDisabled[functions[i]] = toPause;
        }

        emit SetFunctionsState(functions, toPause);
    }

    /// @notice Validate if deposit is allowed
    /// @param depositor The address that is providing collateral
    /// @param recipient The address that will receive the supply tokens
    /// @param amount The amount that is provided
    function validateDeposit(address depositor, address recipient, uint256 amount) external view override {
        if (isFunctionDisabled[IIngress.validateDeposit.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }

        if (pause) {
            revert IN_V1_PROTOCOL_PAUSED();
        }

        if (sanctioned[depositor] || sanctioned[recipient]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }

        uint256 userBalance = IVaultCoreV1(msg.sender).supplyToken().balanceOf(recipient);

        if ((userBalance + amount) < userMinDepositLimit) {
            revert IN_V1_USER_DEPOSIT_MINIMUM_UNMET();
        }

        if (userMaxDepositLimit < amount + userBalance) {
            revert IN_V1_USER_DEPOSIT_LIMIT_EXCEEDED();
        }

        if (
            ILenderStrategy(IVaultCoreV1(msg.sender).activeLenderStrategy()).supplyBalance() + amount >
            vaultDepositLimit
        ) {
            revert IN_V1_VAULT_DEPOSIT_LIMIT_EXCEEDED();
        }
    }

    /// @notice Check if the transaction fits within the rate limit
    /// @param index The type of rate limit to check
    /// @param amount The amount intended to be withdrawn
    /// @return bool if the transaction is within the rate limit
    /// @dev Setting the rate limit period to 0 will disable the rate limit
    function _withinRateLimit(RateLimitType index, uint256 amount) internal returns (bool) {
        RateLimit memory _rateLimit = rateLimit[uint256(index)];

        // Check if rate limit is enabled
        if (_rateLimit.period > 0) {
            // Calculate number of blocks that have passed since the last update
            uint256 passed = block.number - _rateLimit.updated;

            if (passed >= _rateLimit.period) {
                // Reset the rate limit amount if last update was more than a period ago
                _rateLimit.available = _rateLimit.amount;
            } else {
                // Top-up available amount based on the time passed
                _rateLimit.available += (_rateLimit.amount * passed) / _rateLimit.period;
                if (_rateLimit.available > _rateLimit.amount) {
                    _rateLimit.available = _rateLimit.amount;
                }
            }

            // Check if the amount is within the available limit
            if (amount > _rateLimit.available) {
                return false;
            }

            // Update rate limit parameters
            _rateLimit.available -= amount;
            _rateLimit.updated = block.number;
            rateLimit[uint256(index)] = _rateLimit;
        }

        return true;
    }

    /// @notice Validate if withdraw is allowed
    /// @param withdrawer The address the supply will be withdrawn from
    /// @param recipient The address that will receive the withdrawn currency
    function validateWithdraw(address withdrawer, address recipient, uint256 amount) external override {
        if (isFunctionDisabled[IIngress.validateWithdraw.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }

        if (pause) {
            revert IN_V1_PROTOCOL_PAUSED();
        }

        if (sanctioned[withdrawer] || sanctioned[recipient]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }

        if (!_withinRateLimit(RateLimitType.Withdraw, amount)) {
            revert IN_V1_WITHDRAW_RATE_LIMIT();
        }
    }

    /// @notice Validate if borrow is allowed
    /// @param amount amount requested to borrow
    /// @param onBehalfOf account to incur the debt
    /// @param receiver account to receive the tokens
    function validateBorrow(uint256 amount, address onBehalfOf, address receiver) external override {
        if (isFunctionDisabled[IIngress.validateBorrow.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }

        if (pause) {
            revert IN_V1_PROTOCOL_PAUSED();
        }

        if (sanctioned[onBehalfOf] || sanctioned[receiver]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }

        if (!_withinRateLimit(RateLimitType.Borrow, amount)) {
            revert IN_V1_BORROW_RATE_LIMIT();
        }
    }

    /// @notice Validate if repay is allowed
    /// @param repayer Payer of the debt
    /// @param recipient Address the debt is repayed for
    function validateRepay(address repayer, address recipient) external view override {
        if (isFunctionDisabled[IIngress.validateRepay.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }
        if (sanctioned[repayer] && repayer != recipient) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }
    }

    /// @notice Validate if transfer is allowed
    /// @param from Sender of the tokens
    /// @param to Recipient of the tokens
    function validateTransfer(address from, address to) external view override {
        if (isFunctionDisabled[IIngress.validateTransfer.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }

        if (pause) {
            revert IN_V1_PROTOCOL_PAUSED();
        }

        if (sanctioned[from] || sanctioned[to]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }
    }

    /// @notice Validate if claim rewards is allowed
    /// @param claimer Address to check if allowed to claim
    function validateClaimRewards(address claimer, uint256 amount) external override {
        if (isFunctionDisabled[IIngress.validateClaimRewards.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }
        if (pause) {
            revert IN_V1_PROTOCOL_PAUSED();
        }

        if (sanctioned[claimer]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }

        if (!_withinRateLimit(RateLimitType.Claim, amount)) {
            revert IN_V1_CLAIM_RATE_LIMIT();
        }
    }

    /// @notice Validate if commit is allowed
    function validateCommit() external view override {
        if (isFunctionDisabled[IIngress.validateCommit.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }
    }

    /// @notice Validate if rebalance is allowed
    /// @param sender Address calling the rebalance
    function validateRebalance(address sender) external view {
        _checkRole(Roles.GAMMA, sender);

        if (isFunctionDisabled[IIngress.validateRebalance.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }
    }

    /// @notice Validate if liquidate users is allowed
    /// @param liquidator Address to check if allowed to call liquidateUsers
    function validateLiquidateUsers(address liquidator) external view {
        if (isFunctionDisabled[IIngress.validateLiquidateUsers.selector]) {
            revert IN_V1_FUNCTION_PAUSED();
        }
        if (sanctioned[liquidator]) {
            revert IN_V1_ACCOUNT_HAS_BEEN_SANCTIONED();
        }
    }

    /// @notice Validate if snapshotSupplyLoss is allowed
    /// @param sender Address calling the snapshotSupplyLoss
    function validateSnapshotSupplyLoss(address sender) external view {
        _checkRole(Roles.GAMMA, sender);
    }
}
