// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../swap/SwapStrategyConfiguration.sol";
import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/strategy/lending/ILenderStrategy.sol";
import "../../libraries/utils/Utils.sol";

/**
 * @title LenderStrategy
 * @dev Base contract for all lending strategyies to inherit from
 * @author Altitude Labs
 **/

abstract contract LenderStrategy is SwapStrategyConfiguration, ILenderStrategy, ReentrancyGuard {
    address public override vault;
    address public immutable override supplyAsset;
    address public immutable override borrowAsset;
    uint256 public override maxDepositFee;
    uint256 public override supplyPrincipal;
    uint256 public override borrowPrincipal;
    address public override rewardsRecipient;

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert LS_ONLY_VAULT();
        }
        _;
    }

    /// @param vaultAddress The address of the vault that is to use the strategy
    /// @param supplyAssetAddress The address of the token that is to be deposited
    /// @param borrowAssetAddress The address of the token that is to be borrowed
    /// @param depositFee The max fee the lender is allowed to charge the strategy
    /// @param swapStrategyAddress The address of the swap strategy
    /// @param rewardsAddress Where to send any reward tokens
    constructor(
        address vaultAddress,
        address supplyAssetAddress,
        address borrowAssetAddress,
        uint256 depositFee,
        address swapStrategyAddress,
        address rewardsAddress
    ) SwapStrategyConfiguration(swapStrategyAddress) {
        if (vaultAddress == address(0) || supplyAssetAddress == address(0) || borrowAssetAddress == address(0)) {
            revert LS_ZERO_ADDRESS();
        }

        vault = vaultAddress;
        supplyAsset = supplyAssetAddress;
        borrowAsset = borrowAssetAddress;
        maxDepositFee = depositFee;
        rewardsRecipient = rewardsAddress;
    }

    /// @notice Update fee
    /// @param depositFee The max amount the lender provider could charge us on deposit
    function setMaxDepositFee(uint256 depositFee) external override onlyOwner {
        maxDepositFee = depositFee;
        emit SetMaxDepositFee(depositFee);
    }

    /// @notice Supply assets into the market on behalf of `sender` and receive aTokens in exchange
    function deposit(uint256 amount) external override onlyVault returns (uint256) {
        uint256 balanceBefore = supplyBalance();

        if (amount > 0) {
            _deposit(amount);
        }

        _updatePrincipal(0, 0);

        // Flat fee
        if (amount >= maxDepositFee && supplyPrincipal - balanceBefore < amount - maxDepositFee) {
            revert LS_DEPOSIT_FEE_TOO_BIG();
        }

        return supplyPrincipal - balanceBefore;
    }

    /// @notice Redeems lending tokens in exchange for a specified amount of underlying asset
    /// @param amount The amount to be withdrawn
    function withdraw(uint256 amount) external override onlyVault returns (uint256 amountOut) {
        if (amount > 0) {
            amountOut = _withdraw(amount);
        }

        _updatePrincipal(0, 0);
    }

    /// @notice Borrow a specific `amount` of the borrow asset, provided that the borrower has enough supply
    /// @param amount The amount to borrow
    function borrow(uint256 amount) external override onlyVault {
        if (amount > 0) {
            _borrowAndTransfer(amount);
        }

        _updatePrincipal(amount, 0);
    }

    /// @notice Repays a borrowed amount back to the lender
    /// @param amount Amount the user repaid the vault
    function repay(uint256 amount) external override onlyVault {
        if (amount > 0) {
            uint256 actualAmount;
            uint256 currentLenderBalance = borrowBalance();
            if (currentLenderBalance > 0) {
                // Limit repayment to actual debt
                if (amount > currentLenderBalance) {
                    actualAmount = currentLenderBalance;
                } else {
                    actualAmount = amount;
                }

                TransferHelper.safeTransferFrom(borrowAsset, msg.sender, address(this), actualAmount);
                _repay(actualAmount);
            }
        }

        _updatePrincipal(0, amount);
    }

    /// @notice Redeem all aTokens in exchange for the underlying asset
    function withdrawAll() external override onlyVault {
        _withdrawAll();
        _updatePrincipal(0, 0);
    }

    /// @notice Claim and swap reward tokens to farm token
    /// @return rewards An amount of rewards being recognised
    function recogniseRewardsInBase() external override returns (uint256 rewards) {
        _recogniseRewardsInBase(borrowAsset);
        rewards = IERC20(borrowAsset).balanceOf(address(this));
        TransferHelper.safeTransfer(borrowAsset, rewardsRecipient, rewards);

        emit RewardsRecognition(rewards);
    }

    /// @notice If lender borrow is lower than expected, borrow the difference and keep it as vault reserve
    /// @dev This preserves the vault accounting in case of external debt repayment to the lender
    function reconcileBorrowLoss() external onlyOwner {
        uint256 currentBorrow = borrowBalance();
        if (borrowPrincipal > currentBorrow) {
            uint256 amount = borrowPrincipal - currentBorrow;
            _borrowAndTransfer(amount);
            emit ReconcileBorrowLoss(amount);
        }
    }

    /// @notice Check if the supply has been decreased
    /// @return True if the supply has been decreased
    /// @dev If we have supply has gone down on its own, we can assume a supply loss happened
    function hasSupplyLoss() external view returns (bool) {
        return (supplyPrincipal > 0 && supplyPrincipal > supplyBalance());
    }

    /// @notice Calculate reduction in supply and borrow balances
    /// @dev A hook called at the beginning of the supply loss snapshot
    /// @return supplyLoss The amount of supply loss
    /// @return borrowLoss The amount of borrow loss
    /// @return fee The amount of fee (in supplyAsset) paid for the liquidation (if any)
    function preSupplyLossSnapshot()
        public
        virtual
        onlyVault
        returns (uint256 supplyLoss, uint256 borrowLoss, uint256 fee)
    {
        uint256 currentSupply = supplyBalance();
        uint256 currentBorrow = borrowBalance();

        if (supplyPrincipal > currentSupply) {
            supplyLoss = supplyPrincipal - currentSupply;
        }

        if (borrowPrincipal > currentBorrow) {
            borrowLoss = borrowPrincipal - currentBorrow;
        }

        fee = paidLiquidationFee(supplyLoss);
        supplyLoss -= fee;
    }

    /// @notice Keep track of supply and borrow principals as we update the token indexes
    function updatePrincipal() public onlyVault {
        _updatePrincipal(0, 0);
    }

    /// @notice Set supply and borrow principals
    /// @dev Used to preserve the state (which may be a supply/borrow loss) during lender migration
    function resetPrincipal(uint256 supplyPrincial_, uint256 borrowPrincipal_) public onlyVault {
        supplyPrincipal = supplyPrincial_;
        borrowPrincipal = borrowPrincipal_;
    }

    /// @dev Special care of the borrow principal to manage borrow loss (e.g. external repayment to the lender)
    /// @dev If the lender borrow balance is less than expected, the token index is kept unchanged,
    /// @dev as the interest still hasn't covered what was forgiven in the lender (externally repaid)
    function _updatePrincipal(uint256 borrowed, uint256 repaid) internal {
        supplyPrincipal = supplyBalance();
        if (borrowed > 0) {
            borrowPrincipal += borrowed;
        }

        if (repaid > 0) {
            borrowPrincipal = Utils.subOrZero(borrowPrincipal, repaid);
        }

        uint256 currentLenderBorrow = borrowBalance();
        if (currentLenderBorrow > borrowPrincipal) {
            borrowPrincipal = currentLenderBorrow;
        }
    }

    /// @notice Takes tokens from the lending provider and sends them to the vault
    /// @param amount How much to borrow from the lender
    function _borrowAndTransfer(uint256 amount) private {
        uint256 amountToTransfer = IERC20(borrowAsset).balanceOf(address(this));
        _borrow(amount);
        amountToTransfer = IERC20(borrowAsset).balanceOf(address(this)) - amountToTransfer;
        if (amount > amountToTransfer) {
            revert LS_BORROW_INSUFFICIENT(amount, amountToTransfer);
        }
        TransferHelper.safeTransfer(borrowAsset, vault, amountToTransfer);
    }

    /// @notice Lending-specific implementation for total supply balance
    function supplyBalance() public view virtual returns (uint256);

    /// @notice Lending-specific implementation for total borrow balance
    function borrowBalance() public view virtual returns (uint256);

    /// @notice Lending-specific implementation for available borrow liquidity
    function availableBorrowLiquidity() external view virtual returns (uint256);

    /// @notice Lending-specific implementation for deposit
    function _deposit(uint256 amount) internal virtual;

    /// @notice Lending-specific implementation for withdraw
    function _withdraw(uint256 amount) internal virtual returns (uint256 amountOut);

    /// @notice Lending-specific implementation for borrow
    function _borrow(uint256 amount) internal virtual;

    /// @notice Lending-specific implementation for repay
    function _repay(uint256 amount) internal virtual;

    /// @notice Lending-specific implementation for withdrawlAll
    function _withdrawAll() internal virtual;

    /// @notice Lending-specific implementation for rewards recognition
    function _recogniseRewardsInBase(address asset) internal virtual;

    /// @notice Lending-specific implementation for supply loss penalty/fee obtaining
    function paidLiquidationFee(uint256 supplyLoss) public view virtual returns (uint256 fee);
}
