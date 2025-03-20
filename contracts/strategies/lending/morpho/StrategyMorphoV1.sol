// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../LenderStrategy.sol";
import "../../SkimStrategy.sol";
import "../../../libraries/utils/Utils.sol";
import "../../../interfaces/internal/strategy/lending/IMorphoStrategy.sol";

import {IMorpho, Id, MarketParams, Position, Market} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "@morpho-org/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {WAD, MathLib} from "@morpho-org/morpho-blue/src/libraries/MathLib.sol";
import {SharesMathLib} from "@morpho-org/morpho-blue/src/libraries/SharesMathLib.sol";
import {UtilsLib} from "@morpho-org/morpho-blue/src/libraries/UtilsLib.sol";
import {MAX_LIQUIDATION_INCENTIVE_FACTOR, LIQUIDATION_CURSOR} from "@morpho-org/morpho-blue/src/libraries/ConstantsLib.sol";
import {IOracle} from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";

/**
 * @title StrategyMorphoV1
 * @dev Contract for integrating with Morpho Blue
 * @author Altitude Labs
 **/

contract StrategyMorphoV1 is LenderStrategy, SkimStrategy, IMorphoStrategy {
    IMorpho private immutable morphoBlue;
    uint256 private immutable liquidationIncentiveFactor;
    uint8 private immutable oraclePriceDecimals;
    Id public immutable marketId;
    address[] public rewardAssets;

    address public immutable marketLoanToken;
    address public immutable marketCollateralToken;
    address public immutable marketOracle;
    address public immutable marketIrm;
    uint256 public immutable marketLltv;

    /// @param vaultAddress_ The address of the vault that is to use the strategy
    /// @param supplyAssetAddress_ The address of the token that is to be deposited
    /// @param borrowAssetAddress_ The address of the token that is to be borrowed
    /// @param poolAddress_ The address of Morpho Blue
    /// @param marketId_ Morpho's market id
    /// @param maxDepositFee_ The max amount the lender provider could charge us on deposit
    /// @param swapStrategyAddress_ The address of the swap strategy to use for swapping between assets
    /// @param rewardsAddress_ Where to send any reward tokens
    /// @param nonSkimAssets_ Assets that are not allowed for skim
    constructor(
        address vaultAddress_,
        address supplyAssetAddress_,
        address borrowAssetAddress_,
        address poolAddress_,
        Id marketId_,
        uint256 maxDepositFee_,
        address swapStrategyAddress_,
        address rewardsAddress_,
        address[] memory nonSkimAssets_
    )
        LenderStrategy(
            vaultAddress_,
            supplyAssetAddress_,
            borrowAssetAddress_,
            maxDepositFee_,
            swapStrategyAddress_,
            rewardsAddress_
        )
        SkimStrategy(nonSkimAssets_)
    {
        morphoBlue = IMorpho(poolAddress_);
        marketId = marketId_;

        MarketParams memory marketParams = morphoBlue.idToMarketParams(marketId_);
        marketLoanToken = marketParams.loanToken;
        marketCollateralToken = marketParams.collateralToken;
        marketOracle = marketParams.oracle;
        marketIrm = marketParams.irm;
        marketLltv = marketParams.lltv;

        if (supplyAssetAddress_ != marketCollateralToken || borrowAssetAddress_ != marketLoanToken) {
            revert SM_INVALID_MARKET();
        }

        liquidationIncentiveFactor = UtilsLib.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR,
            MathLib.wDivDown(WAD, WAD - MathLib.wMulDown(LIQUIDATION_CURSOR, WAD - marketLltv))
        );

        oraclePriceDecimals =
            36 +
            IERC20Metadata(borrowAssetAddress_).decimals() -
            IERC20Metadata(supplyAssetAddress_).decimals();
    }

    /// @notice Sets the reward tokens to be recognised
    /// @param rewardAssets_ Token addresses
    function setRewardAssets(address[] memory rewardAssets_) external override onlyOwner {
        emit SetRewardAssets(rewardAssets, rewardAssets_);

        rewardAssets = rewardAssets_;
    }

    /// @notice Supply assets into the market on behalf of `sender` and receive tokens in exchange
    /// @param amount The amount to be supplied
    function _deposit(uint256 amount) internal override {
        TransferHelper.safeApprove(supplyAsset, address(morphoBlue), amount);
        morphoBlue.supplyCollateral(
            MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
            amount,
            address(this),
            ""
        );
    }

    /// @notice Withdraws collateral from Morpho
    /// @param amount The amount to be withdrawn
    function _withdraw(uint256 amount) internal override returns (uint256) {
        try
            morphoBlue.withdrawCollateral(
                MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
                amount,
                address(this),
                msg.sender
            )
        {
            return amount;
        } catch {
            revert LS_WITHDRAW_INSUFFICIENT();
        }
    }

    /// @notice Borrow a specific `amount` of the borrow asset, provided that the borrower has enough supply
    /// @param amount The amount to borrow
    function _borrow(uint256 amount) internal override {
        morphoBlue.borrow(
            MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
            amount,
            0,
            address(this),
            address(this)
        );
    }

    /// @notice Repays the already transferred borrowed `amount` on a specific `asset`, burning the equivalent debt
    /// @param amount The amount to repay
    function _repay(uint256 amount) internal override {
        /// @dev This would be invoked by the repay(). It is better to call it ourselves in the beginning,
        ///      instead of doing extra calculations for the shares conversion.
        morphoBlue.accrueInterest(
            MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv)
        );

        TransferHelper.safeApprove(borrowAsset, address(morphoBlue), amount);
        Market memory market = morphoBlue.market(marketId);
        uint256 totalBorrowAssets = market.totalBorrowAssets;
        uint256 totalBorrowShares = market.totalBorrowShares;
        uint256 repayShares = SharesMathLib.toSharesDown(amount, totalBorrowAssets, totalBorrowShares);
        Position memory position = morphoBlue.position(marketId, address(this));

        /// @dev Morpho doc: It is advised to use the shares input when repaying the full position
        ///      to avoid reverts due to conversion roundings between shares and assets.
        if (repayShares > position.borrowShares) {
            morphoBlue.repay(
                MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
                0,
                position.borrowShares,
                address(this),
                ""
            );
        } else {
            morphoBlue.repay(
                MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
                amount,
                0,
                address(this),
                ""
            );
        }

        IERC20(borrowAsset).approve(address(morphoBlue), 0);
    }

    /// @notice Withdraw all collateral from the market
    function _withdrawAll() internal override {
        uint256 balance = supplyBalance();
        if (balance > 0) {
            morphoBlue.withdrawCollateral(
                MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
                balance,
                address(this),
                msg.sender
            );
        }
    }

    /// @notice Returns the address of the lending provider's pool
    /// @return Address of the pool
    function getLendingPool() external view override returns (address) {
        return address(morphoBlue);
    }

    /// @notice Returns the amount of debt by given `asset`
    /// @return Debt amount
    function borrowBalance() public view override returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(
                morphoBlue,
                MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv),
                address(this)
            );
    }

    /// @notice Returns the amount of supply by given `asset`
    /// @return Supply amount
    function supplyBalance() public view override returns (uint256) {
        Position memory position = morphoBlue.position(marketId, address(this));
        return uint256(position.collateral);
    }

    /// @notice Internal reusable function
    /// @param asset The asset to convert to
    function _recogniseRewardsInBase(address asset) internal override {
        for (uint256 i; i < rewardAssets.length; ++i) {
            _swap(rewardAssets[i], asset, type(uint256).max);
        }
    }

    /// @notice Swaps the current balance of fromAsset to toAsset
    /// @param fromAsset asset to swap from
    /// @param toAsset asset to swap to
    function _swap(
        address fromAsset,
        address toAsset,
        uint256 amount
    ) internal {
        if (amount == type(uint256).max) {
            amount = IERC20(fromAsset).balanceOf(address(this));
        }

        if (amount > 0) {
            TransferHelper.safeApprove(fromAsset, address(swapStrategy), amount);

            swapStrategy.swapInBase(fromAsset, toAsset, amount);
        }
    }

    /// @notice Calculates how much one supply token costs in the borrow currency
    /// @param fromAsset Address of the supply token
    /// @param toAsset Address of the borrow token
    /// @return Value of one token in the borrow currency
    function getInBase(address fromAsset, address toAsset) public view override returns (uint256) {
        if (
            (fromAsset != supplyAsset && fromAsset != borrowAsset) ||
            (toAsset != supplyAsset && toAsset != borrowAsset) ||
            (fromAsset == toAsset)
        ) {
            revert LS_INVALID_ASSET_PAIR();
        }

        uint256 price = IOracle(marketOracle).price();

        if (fromAsset == supplyAsset) {
            return Utils.scaleAmount(price, oraclePriceDecimals, IERC20Metadata(toAsset).decimals());
        } else {
            return
                Utils.scaleAmount(
                    10**(oraclePriceDecimals * 2) / price,
                    oraclePriceDecimals,
                    IERC20Metadata(toAsset).decimals()
                );
        }
    }

    /// @notice Calculates value of amount in the borrow currency
    /// @param amount Total supply amount
    /// @param fromAsset Address of the supply token
    /// @param toAsset Address of the borrow token
    /// @return Value of amount in borrow currency
    function convertToBase(
        uint256 amount,
        address fromAsset,
        address toAsset
    ) external view override returns (uint256) {
        return (getInBase(fromAsset, toAsset) * amount) / 10**IERC20Metadata(fromAsset).decimals();
    }

    /// @notice Returns the fee paid on supply loss
    /// @param supplyLoss The amount of supply loss
    function paidLiquidationFee(uint256 supplyLoss) public view override returns (uint256 fee) {
        uint256 liquidatedPrincipal = (supplyLoss * WAD) / liquidationIncentiveFactor;
        fee = supplyLoss - liquidatedPrincipal;
    }

    function availableBorrowLiquidity() external view override returns (uint256 available) {
        (uint256 totalSupply, , uint256 totalBorrow, ) = MorphoBalancesLib.expectedMarketBalances(
            morphoBlue,
            MarketParams(marketLoanToken, marketCollateralToken, marketOracle, marketIrm, marketLltv)
        );

        if (totalSupply > totalBorrow) {
            available = totalSupply - totalBorrow;
            uint256 balance = IERC20Metadata(borrowAsset).balanceOf(address(morphoBlue));
            if (available > balance) {
                available = balance;
            }
        }
    }
}
