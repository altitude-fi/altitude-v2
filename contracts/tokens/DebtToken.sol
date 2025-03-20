// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./InterestToken.sol";
import "../interfaces/internal/tokens/IDebtToken.sol";
import "../interfaces/internal/vault/IVaultCore.sol";

/**
 * @title DebtToken
 * @dev Interest bearing debt token
 * @author Altitude Labs
 **/

contract DebtToken is InterestToken, IDebtToken {
    /// @notice Being non transferable, the DebtToken does not implement any of the standard ERC20 functions for transfer and allowance.
    function transfer(
        address, /* recipient */
        uint256 /* amount */
    ) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        revert DT_TRANSFER_NOT_SUPPORTED();
    }

    /// @notice Being non transferable, the DebtToken does not implement any of the standard ERC20 functions for transfer and allowance.
    function transferFrom(
        address, /* from */
        address, /* to */
        uint256 /* amount */
    ) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        revert DT_TRANSFER_NOT_SUPPORTED();
    }

    /// @notice Being non transferable, the DebtToken does not implement any of the standard ERC20 functions for transfer and allowance.
    function approve(
        address, /* spender */
        uint256 /* amount */
    ) public virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        revert DT_APPROVAL_NOT_SUPPORTED();
    }

    /// @notice Being non transferable, the DebtToken does not implement any of the standard ERC20 functions for transfer and allowance.
    function increaseAllowance(
        address, /* spender */
        uint256 /* amount */
    ) public virtual override returns (bool) {
        revert DT_ALLOWANCE_INCREASE_NOT_SUPPORTED();
    }

    /// @notice Being non transferable, the DebtToken does not implement any of the standard ERC20 functions for transfer and allowance.
    function decreaseAllowance(
        address, /* spender */
        uint256 /* amount */
    ) public virtual override returns (bool) {
        revert DT_ALLOWANCE_DECREASE_NOT_SUPPORTED();
    }

    /// @notice Totaly Supply excluding the latest interest
    /// @return lastStoredTotalSupply
    function storedTotalSupply() public view override(IInterestToken, InterestToken) returns (uint256) {
        return ILenderStrategy(activeLenderStrategy).borrowPrincipal();
    }

    /// @notice Totaly Supply including the latest interest
    /// @return totalSupply
    function totalSupply() public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return ILenderStrategy(activeLenderStrategy).borrowBalance();
    }

    /// @notice Calculates balance including update position. Applies harvest earnings, excludes claimable earnings
    /// @param commit Account position
    /// @return balance The adjusted balance
    function _balanceOf(HarvestTypes.UserCommit memory commit) internal view override returns (uint256) {
        uint256 currentIndex = calcNewIndex();

        commit.position.borrowBalance = Utils.calcBalanceAtIndex(
            commit.position.borrowBalance,
            commit.position.borrowIndex,
            currentIndex
        );

        if (commit.position.borrowBalance < commit.userHarvestUncommittedEarnings) {
            return 0;
        }

        return commit.position.borrowBalance - commit.userHarvestUncommittedEarnings;
    }

    /// @notice Calculates balance up to a given snapshot. Applies harvest earnings, excludes claimable earnings
    /// @param commit Account position
    /// @return balance The adjusted balance
    function _balanceOfAt(HarvestTypes.UserCommit memory commit) internal pure override returns (uint256) {
        if (commit.position.borrowBalance < commit.userClaimableEarnings) {
            return 0;
        }
        return commit.position.borrowBalance - commit.userClaimableEarnings;
    }

    /// @notice Calculates balance, earnings and costs separately
    /// @param account Address to calculate for
    /// @return balance The uncommited balance
    /// @return earnings The uncommited balance
    /// @return claimable The earnigs the user can claim
    function balanceOfDetails(address account)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        HarvestTypes.UserCommit memory commit = IVaultCoreV1(vault).calcCommitUser(account, type(uint256).max);

        uint256 currentIndex = calcNewIndex();

        commit.position.borrowBalance = Utils.calcBalanceAtIndex(
            commit.position.borrowBalance,
            commit.position.borrowIndex,
            currentIndex
        );

        return (commit.position.borrowBalance, commit.userHarvestUncommittedEarnings, commit.userClaimableEarnings);
    }
}
