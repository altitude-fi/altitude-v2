// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../libraries/utils/Utils.sol";
import "../interfaces/internal/vault/IVaultCore.sol";
import "../interfaces/internal/tokens/IInterestToken.sol";
import "../interfaces/internal/strategy/lending/ILenderStrategy.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title InterestToken
 * @dev Interest bearing token that is used to keep & calculate token balances
 * @dev Distributions lenderStrategy interest amongst users
 * @author Altitude Labs
 **/

abstract contract InterestToken is ERC20Upgradeable, IInterestToken {
    uint256 public override MATH_UNITS;

    /** @notice The vault that the token is related to */
    address public override vault;

    /** @notice The token that is used to track interest for */
    address public override underlying;

    /** @notice Strategy that is currently used for lending & borrowing */
    address public override activeLenderStrategy;

    /** @notice Vault Interest tracking index with accrual over time */
    uint256 public override interestIndex;

    /** @dev Interest token decimals */
    uint8 internal _decimals;

    /** @notice Tracks Principal + Accruing Interest for every user */
    mapping(address => uint256) public override userIndex;

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function _onlyVault() internal view {
        if (msg.sender != vault) {
            revert IT_ONLY_VAULT();
        }
    }

    function initialize(
        string memory name,
        string memory symbol,
        address vaultAddress,
        address underlyingAsset,
        address lenderStrategy,
        uint256 mathUnits
    ) external override initializer {
        __ERC20_init(name, symbol);

        MATH_UNITS = mathUnits;
        vault = vaultAddress;
        underlying = underlyingAsset;
        _decimals = IERC20Metadata(underlyingAsset).decimals();

        activeLenderStrategy = lenderStrategy;
        interestIndex = mathUnits;
    }

    /// @notice Decimals of the token
    /// @return decimals
    function decimals() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return _decimals;
    }

    /// @notice Create `amount` of tokens and assigns them to `account`, increasing the total supply.
    /// @param account The account that is depositing/borrowing
    /// @param amount The amount the account is depositing/borrowing
    function mint(address account, uint256 amount) external override onlyVault {
        _userSnapshot(account);
        _mint(account, amount);
    }

    /// @notice Burn `amount` of tokens from `account`, reducing the total supply.
    /// @param account The account that is withdrawing/repaying
    /// @param amount The amount the account is withdrawing/repaying
    function burn(address account, uint256 amount) external override onlyVault {
        _userSnapshot(account);

        uint256 accountBalance = super.balanceOf(account);
        if (amount > accountBalance) {
            amount = accountBalance;
        }

        _burn(account, amount);
    }

    /// @notice Vault transfer on behalf of users
    /// @param owner The owner of the tokens
    /// @param to The recipient of the tokens
    /// @param amount The amount to be transferred
    function vaultTransfer(address owner, address to, uint256 amount) external override onlyVault returns (bool) {
        _accrualTransfer(owner, to, amount);
        return true;
    }

    /// @notice Performs a transfer of supplyTokens between users by:
    /// 1. SupplyLoss the interest being accrued to this moment for both users
    /// 2. Process the transfer
    function _accrualTransfer(address sender, address receiver, uint256 amount) internal {
        if (sender == receiver) {
            revert IT_TRANSFER_BETWEEN_THE_SAME_ADDRESSES();
        }

        _userSnapshot(sender);
        _userSnapshot(receiver);

        _transfer(sender, receiver, amount);
    }

    /// @notice SupplyLoss a user to update their balance accounting for interest accumulated
    function snapshotUser(address account) public override onlyVault returns (uint256, uint256) {
        _userSnapshot(account);

        return (super.balanceOf(account), userIndex[account]);
    }

    /// @notice Updates the index
    function snapshot() external override onlyVault {
        interestIndex = calcNewIndex();
    }

    /// @notice Creates snapshot of the user state
    /// @dev This is needed to be able to account for the accrual of interest per supply/debt Token
    /// Through snapshotting the index is accrued every time an action is taking place (deposit, borrow, etc.)
    /// @param account The address of the user
    function _userSnapshot(address account) internal {
        uint256 _userIndex = userIndex[account];

        if (_userIndex > 0) {
            // Bring the user's token balance to the correct sum at this index.
            uint256 balance = balanceStored(account);

            uint256 newBalance = Utils.calcBalanceAtIndex(balance, _userIndex, interestIndex);

            if (balance > newBalance) {
                // Burn losses
                _burn(account, balance - newBalance);
            } else {
                // Mint interest
                _mint(account, newBalance - balance);
            }
        }

        userIndex[account] = interestIndex;
        emit UserSnapshot(account, interestIndex);
    }

    /// @notice Override the balanceOf function to update user's position due to harvest or supply loss
    /// @param account The address of the user
    function balanceOf(
        address account
    ) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256 userBalance) {
        HarvestTypes.UserCommit memory commit = IVaultCoreV1(vault).calcCommitUser(account, type(uint256).max);

        return _balanceOf(commit);
    }

    /// @notice Returns the balance at a given snapshot
    /// @param account The address of the user
    /// @param account The snapshot id
    function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        HarvestTypes.UserCommit memory commit = IVaultCoreV1(vault).calcCommitUser(account, snapshotId);

        return _balanceOfAt(commit);
    }

    /// @notice Returns the last stored balance for an account
    function balanceStored(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice Vault sets the new active strategy if needed
    /// @dev In case of having a fee in the new lending strategy, the index should be updated
    /// @param newStrategy The address of the new strategy
    function setActiveLenderStrategy(address newStrategy) external override onlyVault {
        activeLenderStrategy = newStrategy;
    }

    /// @notice Calculates the new index based on the latest balances
    /// @return interestIndex_ The new interest index
    function calcNewIndex() public view override returns (uint256) {
        return calcIndex(storedTotalSupply());
    }

    /// @notice Calculates the index based on a given balance
    /// @dev The index only goes up
    /// @dev Unexpected lender supply reduction is handled by SupplyLossManager
    /// @dev Unexpected lender borrow reduction is handled by freezing the index until we reach again the corresponding borrowPrincipal
    /// @dev New index is based on the total lending strategy balance and the balance provided
    /// @return interestIndex_ The new interest index
    function calcIndex(uint256 balanceOld) public view returns (uint256) {
        uint256 interestIndex_ = interestIndex;
        uint256 balanceNew = totalSupply();

        if (balanceOld > 0 && balanceNew > 0 && balanceOld < balanceNew) {
            interestIndex_ = _calcIndexIncrease(interestIndex_, balanceOld, balanceNew);
        }

        return interestIndex_;
    }

    /// @notice In case the lender balance is bigger than the last one being stored, account for the interest accumulation
    /// @param interestIndex_ The last stored interest index
    /// @param balancePrev The last stored balance
    /// @param balanceNew The balance in lender
    /// @return newInterestIndex The new index accounting for interest accumulation
    function _calcIndexIncrease(
        uint256 interestIndex_,
        uint256 balancePrev,
        uint256 balanceNew
    ) internal pure returns (uint256) {
        uint256 indexIncrease = Utils.divRoundingUp(interestIndex_ * (balanceNew - balancePrev), balancePrev);

        return interestIndex_ + indexIncrease;
    }

    /// @notice [IMPORTANT] Sets account balance bypassing all validations.
    /// @dev use only in case of supply loss to avoid accumulating interest by mistake
    /// @param account The account the balance to be set for
    /// @param newBalance The new balance of the account
    /// @param newIndex The new index of the account
    function setBalance(address account, uint256 newBalance, uint256 newIndex) external override onlyVault {
        userIndex[account] = newIndex;
        uint256 oldBalance = super.balanceOf(account);

        if (oldBalance > newBalance) {
            _burn(account, oldBalance - newBalance);
        } else {
            _mint(account, newBalance - oldBalance);
        }
    }

    /// @notice [IMPORTANT] Updates the last stored index.
    /// @dev Used in case interest accumulated before the supply loss and snapshot have happened
    function setInterestIndex(uint256 newIndex) external onlyVault {
        interestIndex = newIndex;
    }

    /// @notice A function to be handled and modified by the tokens to apply adjustments if needed
    /// param Updated position of an account
    /// return The current balance of an account
    function _balanceOf(HarvestTypes.UserCommit memory) internal view virtual returns (uint256);

    /// @notice A function to be handled and modified by the tokens to apply adjustments if needed
    /// param Updated position of an account
    /// return The balance of an account up to a given snapshot
    function _balanceOfAt(HarvestTypes.UserCommit memory) internal pure virtual returns (uint256);

    /// @notice Totaly Supply excluding the latest interest
    /// @return lastStoredTotalSupply
    function storedTotalSupply() public view virtual returns (uint256);
}
