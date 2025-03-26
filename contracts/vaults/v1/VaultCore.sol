// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./extensions/groomable/GroomableVault.sol";
import "./extensions/configurable/ConfigurableVault.sol";
import "./extensions/liquidatable/LiquidatableVault.sol";
import "./extensions/snapshotable/SnapshotableVault.sol";
import "../../libraries/utils/HealthFactorCalculator.sol";
import "../../libraries/uniswap-v3/TransferHelper.sol";

import "../../interfaces/internal/access/IIngress.sol";
import "../../interfaces/internal/vault/IVaultCore.sol";
import "../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";

/**
 * @title VaultCoreV1
 * @author Altitude Labs
 * @notice Main contract for users to interact with.
 *         Key user functions include deposit, borrow, repay, withdraw and claim
 * @dev To be covered by a proxy contract
 **/

abstract contract VaultCoreV1 is
    ConfigurableVaultV1,
    GroomableVaultV1,
    LiquidatableVaultV1,
    SnapshotableVaultV1,
    IVaultCoreV1
{
    /** @notice check if sender is wrapped supply token contract */
    modifier onlySupplyToken() {
        if (address(supplyToken) != msg.sender) {
            revert VC_V1_NOT_AUTHORIZED_TO_DEAL_WITH_TRANSFERS();
        }
        _;
    }

    /** @notice check if allowee has been approved to act on behalf of another address */
    modifier onlyAllowedOnBehalf(address allowee, address allower, bytes4 selector) {
        if (allower != allowee && !allowOnBehalfList[allower][allowee] && !onBehalfFunctions[selector]) {
            revert VC_V1_NOT_ALLOWED_TO_ACT_ON_BEHALF();
        }
        _;
    }

    /// @notice Validate if the transfer can proceed, if so update user's position
    /// @param from The address from which the transfer will take place
    /// @param to The address receiving the transfer
    /// @param transferSelector TransferSelector
    function preTransfer(
        address from,
        address to,
        uint256, // amount param is to stay open for upgradability
        bytes4 transferSelector
    ) external override onlySupplyToken onlyAllowedOnBehalf(from, to, transferSelector) nonReentrant {
        IIngress(ingressControl).validateTransfer(from, to);
        updatePosition(from);
        updatePosition(to);
    }

    /// @notice Post transfer, update user block number for harvest distribution tracking
    /// @param from The address sending the funds
    /// @param to The address receiving the transfer
    function postTransfer(address from, address to) external onlySupplyToken {
        _validateHealthFactor(from, 0, 0);

        userLastDepositBlock[to] = block.number;
        _updateEarningsRatio(to);
    }

    /// @notice User transfers the supply asset of the vault and receives supplyTokens in exchange
    /// @param amount Amount to deposit
    /// @param onBehalfOf Address to deposit on behalf of
    function deposit(uint256 amount, address onBehalfOf) external payable override(IVaultCoreV1) nonReentrant {
        updatePosition(onBehalfOf);
        _deposit(amount, onBehalfOf);
    }

    /// @notice User borrows the borrow asset from the vault
    /// @param amount Amount to borrow
    function borrow(uint256 amount) external override nonReentrant {
        updatePosition(msg.sender);
        _borrow(amount, msg.sender, msg.sender);
    }

    /// @notice A pre-approved user borrows assets on behalf of another user
    /// @param amount The amount to borrow
    /// @param onBehalfOf The address incurring the debt
    /// @param deadline Expiry date of the signature in Unix time
    /// @param signature onBehalfOf's approval signature for these parameters
    function borrowOnBehalfOf(
        uint256 amount,
        address onBehalfOf,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        // Verify the transaction has been approved by the onBehalfOf user
        borrowVerifier.verifyAndBurnNonce(amount, onBehalfOf, msg.sender, deadline, signature);
        updatePosition(onBehalfOf);
        _borrow(amount, onBehalfOf, msg.sender);
    }

    /// @notice User transfers supplyTokens and receives the vault supply assets in return
    /// @param amount Amount to withdraw
    /// @param to Recipient address for the withdraw
    /// @return Actual amount that was withdrawn
    function withdraw(uint256 amount, address to) external override nonReentrant returns (uint256) {
        updatePosition(msg.sender);
        return _withdraw(amount, to);
    }

    /// @notice User transfers vault borrow assets to reduce their own debt
    //          or the debt of another user who has approved them to repay
    /// @param amount Amount to repay
    /// @param onBehalfOf Address of the debt holder
    /// @return Actual amount that was repaid
    function repay(uint256 amount, address onBehalfOf) external override nonReentrant returns (uint256) {
        updatePosition(onBehalfOf);
        return _repay(amount, onBehalfOf);
    }

    /// @notice Repay any bad debt (bypassing the allowOnBehalfList) for any user
    /// @param amount Amount to repay
    /// @param onBehalfOf Address of the debt holder
    /// @return repayAmount Actual amount that was repaid
    function repayBadDebt(
        uint256 amount,
        address onBehalfOf
    ) external override nonReentrant returns (uint256 repayAmount) {
        _validateRepay(onBehalfOf, amount);
        updatePosition(onBehalfOf);

        // Confirm the user has no supplyTokens
        // If the user is liquidatable but still has supplyTokens
        // they should be fully liquidated first
        if (supplyToken.balanceOf(onBehalfOf) > 0) {
            revert VC_V1_USER_HAS_SUPPLY();
        }

        repayAmount = _repayUnchecked(amount, onBehalfOf);
        emit RepayBadDebt(msg.sender, onBehalfOf, repayAmount);
    }

    /// @notice Deposit and borrow in a single transaction
    /// @param depositAmount Amount to be deposited
    /// @param borrowAmount Amount to be borrowed
    function depositAndBorrow(uint256 depositAmount, uint256 borrowAmount) external payable override nonReentrant {
        updatePosition(msg.sender);
        _deposit(depositAmount, msg.sender);
        _borrow(borrowAmount, msg.sender, msg.sender);
    }

    /// @notice Repay debt and withdraw supply in one transaction
    /// @param repayAmount Borrow amount to be repaid
    /// @param withdrawAmount Supply amount to be withdrawn
    /// @param to Account to withdraw supply assets to
    /// @return ( repaid, withdrawn ) Actual amount repaid and withdrawn
    function repayAndWithdraw(
        uint256 repayAmount,
        uint256 withdrawAmount,
        address to
    ) external override nonReentrant returns (uint256, uint256) {
        updatePosition(msg.sender);

        uint256 repaid = _repay(repayAmount, msg.sender);
        uint256 withdrawn = _withdraw(withdrawAmount, to);
        return (repaid, withdrawn);
    }

    /// @notice Internal function to deposit `amount` of the supply asset and transfer equivalent supplyTokens
    /// @param amount amount to deposit
    /// @param onBehalfOf user address on who's behalf the deposit is made
    /// 1. It validates that the deposit can be proceed by checking the limits
    /// 2. Mint supplyTokens(supply tokens) that accrue interest
    /// 3. Deposit in the lender provider
    function _deposit(uint256 amount, address onBehalfOf) internal {
        // Gets the deposit amount into this contract as ERC20
        _preDeposit(amount);

        // Validate the deposit
        _validateDeposit(onBehalfOf, amount);

        TransferHelper.safeTransfer(supplyUnderlying, activeLenderStrategy, amount);

        uint256 amountDeposited = ILenderStrategy(activeLenderStrategy).deposit(amount);

        supplyToken.mint(onBehalfOf, amountDeposited);

        _updateEarningsRatio(onBehalfOf);
        userLastDepositBlock[onBehalfOf] = block.number;

        emit Deposit(msg.sender, onBehalfOf, amount);
    }

    /// @notice Internal function to borrow the vaults borrow asset
    /// @param amount Amount to borrow
    /// @param onBehalfOf The address incurring the debt
    /// @param receiver The address receiving the borrowed amount
    function _borrow(uint256 amount, address onBehalfOf, address receiver) internal {
        _validateBorrow(onBehalfOf, amount);

        uint256 desiredBorrow = amount;

        // Check how much we can borrow from the lenderStrategy
        uint256 availableBorrow = HealthFactorCalculator.availableBorrow(
            supplyThreshold,
            ILenderStrategy(activeLenderStrategy).convertToBase(
                ILenderStrategy(activeLenderStrategy).supplyBalance(),
                supplyUnderlying,
                borrowUnderlying
            ),
            ILenderStrategy(activeLenderStrategy).borrowBalance()
        );

        // Withdraw from the farmStrategy if needed to support borrow
        if (availableBorrow < desiredBorrow) {
            uint256 toWithdraw = desiredBorrow - availableBorrow;
            desiredBorrow = availableBorrow;

            if (IFarmDispatcher(activeFarmStrategy).withdraw(toWithdraw) < toWithdraw) {
                revert VC_V1_FARM_WITHDRAW_INSUFFICIENT();
            }

            debtToken.vaultTransfer(address(this), onBehalfOf, toWithdraw);
        }

        // Borrow from the lenderStrategy to support borrow
        if (desiredBorrow > 0) {
            debtToken.mint(onBehalfOf, desiredBorrow);
            ILenderStrategy(activeLenderStrategy).borrow(desiredBorrow);
        }

        TransferHelper.safeTransfer(borrowUnderlying, receiver, amount);

        emit Borrow(msg.sender, onBehalfOf, amount);
    }

    /// @notice Internal function to transfer supplyTokens and receive the vault supply assets in return
    /// @param amount Amount to withdraw
    /// @param to Recipient address for the withdraw
    /// @return withdrawAmount amount that was withdrawn
    function _withdraw(uint256 amount, address to) internal returns (uint256 withdrawAmount) {
        // Limit withdraw to userBalance
        withdrawAmount = amount;
        uint256 userBalance = supplyToken.balanceOf(msg.sender);
        if (withdrawAmount > userBalance) {
            withdrawAmount = userBalance;
        }

        _validateWithdraw(msg.sender, to, withdrawAmount);

        (uint256 withdrawFee, ) = calcWithdrawFee(msg.sender, withdrawAmount);
        withdrawAmount -= withdrawFee;

        uint256 targetBorrow;
        uint256 totalSupplyBalance = ILenderStrategy(activeLenderStrategy).supplyBalance();

        // totalSupplyBalance could be lower than withdrawAmount with a few wei for the last user
        if (totalSupplyBalance >= withdrawAmount) {
            // Calculate the target borrow for the new target supply (= current - withdraw)
            targetBorrow = HealthFactorCalculator.targetBorrow(
                activeLenderStrategy,
                supplyUnderlying,
                borrowUnderlying,
                targetThreshold,
                totalSupplyBalance - withdrawAmount
            );
        } else {
            // The total sum of the users balances is slightly bigger then the one in the lender
            // The last user exisitng the system is to withdraw a little less
            withdrawAmount = totalSupplyBalance;
        }

        uint256 totalBorrowBalance = ILenderStrategy(activeLenderStrategy).borrowBalance();

        // Withdraw from the FarmStrategy and repay part of the lenderStrategy debt if needed
        if (totalBorrowBalance > targetBorrow) {
            uint256 borrowToRepay = totalBorrowBalance - targetBorrow;
            uint256 vaultBorrow = debtToken.balanceOf(address(this));
            if (borrowToRepay > vaultBorrow) {
                // We should repay at most the vault's portion of the lender borrow balance.
                borrowToRepay = vaultBorrow;
            }

            if (IFarmDispatcher(activeFarmStrategy).withdraw(borrowToRepay) < borrowToRepay) {
                revert VC_V1_FARM_WITHDRAW_INSUFFICIENT();
            }
            debtToken.burn(address(this), borrowToRepay);

            TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, borrowToRepay);
            ILenderStrategy(activeLenderStrategy).repay(borrowToRepay);
        }

        bool vaultBecomesUnhealthy = !HealthFactorCalculator.isPositionHealthy(
            activeLenderStrategy,
            supplyUnderlying,
            borrowUnderlying,
            liquidationThreshold,
            ILenderStrategy(activeLenderStrategy).supplyBalance() - withdrawAmount,
            ILenderStrategy(activeLenderStrategy).borrowBalance()
        );

        if (vaultBecomesUnhealthy) {
            revert VC_V1_UNHEALTHY_VAULT_RISK();
        }

        // Adjust the withdrawAmount to the actual being withdrawn
        uint256 realAmountWithdrawn = ILenderStrategy(activeLenderStrategy).withdraw(withdrawAmount);
        // Add possible lending Protocol fees
        uint256 lenderFee;
        if (realAmountWithdrawn < withdrawAmount) {
            lenderFee = withdrawAmount - realAmountWithdrawn;
        }

        _applyWithdrawal(msg.sender, withdrawFee, withdrawAmount, userBalance);

        emit Withdraw(msg.sender, to, withdrawAmount, withdrawFee, lenderFee);

        return _postWithdraw(realAmountWithdrawn, to);
    }

    function calcWithdrawFee(
        address account,
        uint256 withdrawAmount
    ) public view returns (uint256 withdrawFee, uint256 feeExpiresAfter) {
        uint256 blockPassed = block.number - userLastDepositBlock[account];
        if (withdrawFeePeriod >= blockPassed) {
            withdrawFee = (withdrawAmount * withdrawFeeFactor) / 1e18; // 1e18 represents a 100%. withdrawFeeFactor is in percentage
            feeExpiresAfter = withdrawFeePeriod - blockPassed;
        }
    }

    function _applyWithdrawal(
        address account,
        uint256 withdrawFee,
        uint256 withdrawAmount,
        uint256 maxWithdrawalAmount
    ) internal {
        // Manually apply the fee to be distributed among all the users by increasing the index
        uint256 balanceNow = supplyToken.storedTotalSupply();

        uint256 indexIncrease = supplyToken.calcIndex(balanceNow - withdrawFee);
        supplyToken.setInterestIndex(indexIncrease);

        // Don't include user into the fee distribution
        supplyToken.setBalance(account, maxWithdrawalAmount - (withdrawAmount + withdrawFee), indexIncrease);
    }

    /// @notice Internal function to transfer vault debtTokens to reduce users debt
    /// @param amount Amount to repay
    /// @param onBehalfOf Address of the debt holder
    /// @return repayAmount amount that was repaid
    function _repay(
        uint256 amount,
        address onBehalfOf
    ) internal onlyAllowedOnBehalf(msg.sender, onBehalfOf, IVaultCoreV1.repay.selector) returns (uint256 repayAmount) {
        _validateRepay(onBehalfOf, amount);
        repayAmount = _repayUnchecked(amount, onBehalfOf);

        emit Repay(msg.sender, onBehalfOf, repayAmount);
    }

    /// @notice Internal function to perform the actual repayment
    /// @param amount Amount to repay
    /// @param onBehalfOf Address of the debt holder
    /// @return repayAmount amount that was repaid
    /// @dev params should be validated beforehand
    function _repayUnchecked(uint256 amount, address onBehalfOf) internal returns (uint256 repayAmount) {
        uint256 userBalance = debtToken.balanceOf(onBehalfOf);
        if (userBalance > 0) {
            repayAmount = amount;

            // Repay upto the users balance of the borrow asset
            if (userBalance < repayAmount) {
                repayAmount = userBalance;
            }

            TransferHelper.safeTransferFrom(borrowUnderlying, msg.sender, address(this), repayAmount);

            debtToken.burn(onBehalfOf, repayAmount);

            // Only repay the lenderStrategy if there is outstanding debt to repay
            uint256 currentLenderBalance = ILenderStrategy(activeLenderStrategy).borrowBalance();

            if (currentLenderBalance > 0) {
                // Limit the repayment amount to the existing debt
                if (repayAmount > currentLenderBalance) {
                    repayAmount = currentLenderBalance;
                }
                TransferHelper.safeApprove(borrowUnderlying, activeLenderStrategy, repayAmount);
                ILenderStrategy(activeLenderStrategy).repay(repayAmount);
            }

            _updateEarningsRatio(onBehalfOf);
        }
    }

    /// @notice Validate if the deposit can proceed
    /// @param account account to check
    /// @param amount amount being deposited
    function _validateDeposit(
        address account,
        uint256 amount
    ) internal view onlyAllowedOnBehalf(msg.sender, account, IVaultCoreV1.deposit.selector) {
        IIngress(ingressControl).validateDeposit(msg.sender, account, amount);
        if (amount == 0) {
            revert VC_V1_INVALID_DEPOSIT_AMOUNT();
        }
    }

    /// @notice Validate if the borrow can proceed
    /// @param account account to check
    /// @param amount amount requested to borrow
    /// @dev We should call this function after the account's position has been updated
    function _validateBorrow(address account, uint256 amount) internal {
        IIngress(ingressControl).validateBorrow(msg.sender, account, amount);

        if (amount == 0) {
            revert VC_V1_INVALID_BORROW_AMOUNT();
        }

        _validateHealthFactor(account, 0, amount);
    }

    /// @notice Validate if the repay can proceed
    /// @param amount amount to be repaid
    function _validateRepay(address onBehalf, uint256 amount) internal view {
        IIngress(ingressControl).validateRepay(msg.sender, onBehalf);

        if (amount == 0) {
            revert VC_V1_INVALID_REPAY_AMOUNT();
        }
    }

    /// @notice Validate if the withdraw can proceed
    function _validateWithdraw(address withdrawer, address recipient, uint256 amount) internal {
        IIngress(ingressControl).validateWithdraw(withdrawer, recipient, amount);

        if (amount == 0) {
            revert VC_V1_INVALID_WITHDRAW_AMOUNT();
        }
        _validateHealthFactor(withdrawer, amount, 0);
    }

    /// @notice Validate if the user position will remain healthy after withdraw
    /// @param from The user to check the healh factor for
    /// @param supplyAmount The supply amount to be taken
    /// @param borrowAmount The borrow amount to be taken
    /// @dev We should call this function after the from account's position has been updated
    function _validateHealthFactor(address from, uint256 supplyAmount, uint256 borrowAmount) internal view {
        if (
            !HealthFactorCalculator.isPositionHealthy(
                activeLenderStrategy,
                supplyUnderlying,
                borrowUnderlying,
                supplyThreshold,
                supplyToken.balanceOf(from) - supplyAmount,
                debtToken.balanceOf(from) + borrowAmount
            )
        ) {
            revert VC_V1_NOT_ENOUGH_SUPPLY();
        }
    }

    /* ------- Abstract functions ------- */
    /** @notice handle funds transfers from an address as they could be native or ERC20 tokens */
    function _preDeposit(uint256) internal virtual;

    /** @notice handle funds transfers to an address as they could be native or ERC20 tokens */
    function _postWithdraw(uint256, address) internal virtual returns (uint256);
}
