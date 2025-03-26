// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./InterestToken.sol";
import "../interfaces/internal/vault/IVaultCore.sol";
import "../interfaces/internal/tokens/ISupplyToken.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SupplyToken
 * @dev Interest bearing supply token
 * @author Altitude Labs
 **/

contract SupplyToken is InterestToken, ISupplyToken, ReentrancyGuard {
    // modifier to check if the user has enough balance
    modifier onlyEnoughBalance(address owner, uint256 amount) {
        if (balanceOf(owner) < amount) {
            revert ST_NOT_ENOUGH_BALANCE();
        }
        _;
    }

    /// @notice Transfer tokens on behalf of another user
    /// @param from The owner of the tokens
    /// @param to The recipient of the tokens
    /// @param amount The amount to be transferred
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) onlyEnoughBalance(from, amount) nonReentrant returns (bool) {
        _transferFrom(from, to, amount, amount, IERC20Upgradeable.transferFrom.selector);
        return true;
    }

    /// @notice Transfer the entire balance of tokens including all the interest on behalf of another user
    /// @param from The owner of the tokens
    /// @param to The recipient of the tokens
    function transferFromMax(address from, address to) external nonReentrant returns (bool) {
        uint256 amount = balanceOf(from);
        _transferFrom(from, to, amount, type(uint256).max, IERC20Upgradeable.transferFrom.selector);

        return true;
    }

    /// @notice Re-usable function to process transferFrom for both max and desired amounts
    /// @param from The owner of the tokens
    /// @param to The recipient of the tokens
    /// @param amount The amount to be transferred
    /// @param desiredAllowance The amount to be transferred
    /// @param transferSelector selector
    function _transferFrom(
        address from,
        address to,
        uint256 amount,
        uint256 desiredAllowance,
        bytes4 transferSelector
    ) internal {
        IVaultCoreV1(vault).preTransfer(from, to, amount, transferSelector);

        uint256 currentAllowance = allowance(from, msg.sender);
        if (desiredAllowance > currentAllowance) {
            revert ST_NOT_ENOUGH_ALLOWANCE();
        }

        _accrualTransfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - desiredAllowance);

        IVaultCoreV1(vault).postTransfer(from, to);
    }

    /// @notice Transfer tokens between users
    /// @param to The recipient of the tokens
    /// @param amount The amount to be transferred
    function transfer(
        address to,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20Upgradeable)
        onlyEnoughBalance(msg.sender, amount)
        nonReentrant
        returns (bool)
    {
        return _transferTo(to, amount);
    }

    /// @notice Transfer the entire balance of tokens including all the interest
    /// @param to The recipient of the tokens
    function transferMax(address to) external override nonReentrant returns (bool) {
        uint256 amount = balanceOf(msg.sender);
        return _transferTo(to, amount);
    }

    /// @notice Re-usable function to process transfer for both max and desired amounts
    /// @param to The recipient of the tokens
    /// @param amount The amount to be transferred
    function _transferTo(address to, uint256 amount) internal returns (bool) {
        IVaultCoreV1(vault).preTransfer(msg.sender, to, amount, IERC20Upgradeable.transfer.selector);
        _accrualTransfer(msg.sender, to, amount);
        IVaultCoreV1(vault).postTransfer(msg.sender, to);

        return true;
    }

    /// @notice Totaly Supply excluding the latest interest
    /// @return lastStoredTotalSupply
    function storedTotalSupply() public view override(IInterestToken, InterestToken) returns (uint256) {
        return ILenderStrategy(activeLenderStrategy).supplyPrincipal();
    }

    /// @notice Totaly Supply including the latest interest
    /// @return totalSupply
    function totalSupply() public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return ILenderStrategy(activeLenderStrategy).supplyBalance();
    }

    /// @dev Overrides the balanceOf function to revert in case of vault
    function balanceOf(
        address account
    ) public view override(IERC20Upgradeable, InterestToken) returns (uint256 userBalance) {
        // Skip position update for the vault
        if (account == vault) {
            return 0;
        }

        return super.balanceOf(account);
    }

    /// @notice Calculates additional params that apply to the balance
    /// @param commit Account commit data
    /// @return balance The adjusted balance
    function _balanceOf(HarvestTypes.UserCommit memory commit) internal view override returns (uint256) {
        uint256 currentIndex = calcNewIndex();

        commit.position.supplyBalance = Utils.calcBalanceAtIndex(
            commit.position.supplyBalance,
            commit.position.supplyIndex,
            currentIndex
        );

        return commit.position.supplyBalance;
    }

    /// @notice Calculates balance up to a given snapshot
    /// @param commit Account position
    /// @return balance The adjusted balance
    function _balanceOfAt(HarvestTypes.UserCommit memory commit) internal pure override returns (uint256) {
        return commit.position.supplyBalance;
    }
}
