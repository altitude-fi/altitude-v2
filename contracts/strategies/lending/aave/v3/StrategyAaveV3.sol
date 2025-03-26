// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../LenderStrategy.sol";

import "../../../../interfaces/external/strategy/lending/Aave/IAaveDebtToken.sol";
import "../../../../interfaces/external/strategy/lending/Aave/IProtocolDataProvider.sol";
import "../../../../interfaces/external/strategy/lending/Aave/v3/ILendingPool.sol";
import "../../../../interfaces/external/strategy/lending/Aave/v3/IPoolAddressesProvider.sol";
import "../../../../interfaces/external/strategy/lending/Aave/v3/IPriceOracleGetter.sol";
import "../../../../interfaces/external/strategy/lending/Aave/v3/IRewardsController.sol";

/**
 * @title StrategyAaveV3
 * @dev Contract for integrating with Aave v3 lending protocol
 * @author Altitude Labs
 **/

contract StrategyAaveV3 is LenderStrategy {
    IAaveLendingPoolV3 private immutable pool;
    IProtocolDataProvider private immutable dataProvider;
    IRewardsController private immutable rewardsController;
    IPoolAddressesProvider private immutable poolAddressesProvider;

    /// @param vaultAddress The address of the vault that is to use the strategy
    /// @param supplyAssetAddress The address of the token that is to be deposited
    /// @param borrowAssetAddress The address of the token that is to be borrowed
    /// @param poolAddress The address of the Aave lending pool
    /// @param poolAddressesProviderAddress The address of the Aave addresses provider
    /// @param dataProviderAddress The address of the Aave data provider
    /// @param rewardsControllerAddress The address of the Aave rewards controller
    /// @param maxDepositFee The max amount the lender provider could charge us on deposit
    /// @param swapStrategyAddress The address of the swap strategy to use for swapping between assets
    /// @param rewardsAddress Where to send any reward tokens
    constructor(
        address vaultAddress,
        address supplyAssetAddress,
        address borrowAssetAddress,
        address poolAddress,
        address poolAddressesProviderAddress,
        address dataProviderAddress,
        address rewardsControllerAddress,
        uint256 maxDepositFee,
        address swapStrategyAddress,
        address rewardsAddress
    )
        LenderStrategy(
            vaultAddress,
            supplyAssetAddress,
            borrowAssetAddress,
            maxDepositFee,
            swapStrategyAddress,
            rewardsAddress
        )
    {
        pool = IAaveLendingPoolV3(poolAddress);
        dataProvider = IProtocolDataProvider(dataProviderAddress);
        poolAddressesProvider = IPoolAddressesProvider(poolAddressesProviderAddress);
        rewardsController = IRewardsController(rewardsControllerAddress);
    }

    /// @notice Supply assets into the market on behalf of `sender` and receive aTokens in exchange
    function _deposit(uint256 amount) internal override {
        TransferHelper.safeApprove(supplyAsset, address(pool), amount);
        pool.deposit(supplyAsset, amount, address(this), 0);
    }

    /// @notice Redeems aTokens in exchange for a specified amount of underlying asset
    /// @param amount The amount to be withdrawn
    function _withdraw(uint256 amount) internal override returns (uint256 amountOut) {
        try pool.withdraw(supplyAsset, amount, msg.sender) returns (uint256 _amount) {
            amountOut = _amount;
        } catch {
            revert LS_WITHDRAW_INSUFFICIENT();
        }
    }

    /// @notice Borrow a specific `amount` of the borrow asset, provided that the borrower has enough supply
    /// @param amount The amount to borrow
    function _borrow(uint256 amount) internal override {
        pool.borrow(borrowAsset, amount, 2, 0, address(this));
    }

    /// @notice Repays the already transferred borrowed `amount` on a specific `asset`, burning the equivalent debt
    /// @param amount The amount to repay
    function _repay(uint256 amount) internal override {
        TransferHelper.safeApprove(borrowAsset, address(pool), amount);
        pool.repay(borrowAsset, amount, 2, address(this));
    }

    /// @notice Redeem all aTokens in exchange for the underlying asset
    function _withdrawAll() internal override {
        if (supplyBalance() > 0) {
            pool.withdraw(supplyAsset, type(uint256).max, msg.sender);
        }
    }

    /// @notice Returns the address of the lending provider's pool
    /// @return Address of Aave lending pool
    function getLendingPool() external view override returns (address) {
        return address(pool);
    }

    /// @notice Returns the amount of debt by given `asset`
    /// @return Debt amount
    function borrowBalance() public view override returns (uint256) {
        (, , address variableDebtTokenAddress) = dataProvider.getReserveTokensAddresses(borrowAsset);

        return IAaveDebtToken(variableDebtTokenAddress).balanceOf(address(this));
    }

    /// @notice Returns the amount of supply by given `asset`
    /// @return Supply amount
    function supplyBalance() public view override returns (uint256) {
        (address aToken, , ) = dataProvider.getReserveTokensAddresses(supplyAsset);

        return IERC20(aToken).balanceOf(address(this));
    }

    /// @notice Reusable internal function to recognise rewards
    /// @dev In all cases except withdraw rewards should be recognized in the borrow asset
    /// @param asset asset to recognise rewards in
    function _recogniseRewardsInBase(address asset) internal override {
        address[] memory addresses = new address[](2);
        (addresses[0], , ) = dataProvider.getReserveTokensAddresses(supplyAsset);
        (, , addresses[1]) = dataProvider.getReserveTokensAddresses(borrowAsset);

        (address[] memory rewardsList, uint256[] memory claimedAmounts) = rewardsController.claimAllRewardsToSelf(
            addresses
        );

        uint256 rewardsCount = rewardsList.length;
        for (uint256 i; i < rewardsCount; ) {
            _swap(rewardsList[i], asset, claimedAmounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Swaps the current balance of fromAsset to toAsset
    /// @param fromAsset asset to swap from
    /// @param toAsset asset to swap to
    function _swap(address fromAsset, address toAsset, uint256 amount) internal {
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
        address[] memory addresses = new address[](2);
        addresses[0] = fromAsset;
        addresses[1] = toAsset;
        uint256[] memory prices = IPriceOracleGetterV3(poolAddressesProvider.getPriceOracle()).getAssetsPrices(
            addresses
        );

        return (prices[0] * (10 ** IERC20Metadata(toAsset).decimals())) / prices[1];
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
        return (getInBase(fromAsset, toAsset) * amount) / 10 ** IERC20Metadata(fromAsset).decimals();
    }

    /// @notice Returns the paid supply loss fee
    function paidLiquidationFee(uint256 supplyLoss) public view override returns (uint256 fee) {
        (, , , uint256 penalty, , , , , , ) = dataProvider.getReserveConfigurationData(borrowAsset);

        uint256 liquidatedPrincipal = (supplyLoss * 1e4) / penalty;
        fee = supplyLoss - liquidatedPrincipal;
    }

    /// @notice Available liquidity at the lending provider
    function availableBorrowLiquidity() external view override returns (uint256 available) {
        (address aToken, , ) = dataProvider.getReserveTokensAddresses(borrowAsset);

        available = IERC20Metadata(borrowAsset).balanceOf(aToken);
    }
}
