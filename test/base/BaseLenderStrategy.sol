// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {TokensGenerator} from "../utils/TokensGenerator.sol";
import {IPriceSource} from "../../contracts/interfaces/internal/oracles/IPriceSource.sol";
import "../../contracts/strategies/lending/LenderStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract BaseLenderStrategy is LenderStrategy, TokensGenerator {
    uint256 public totalDeposited;
    uint256 public totalBorrowed;

    uint256 public withdrawFee;
    uint256 public feeLoss;
    uint256 public depositFee;
    uint256 public depositRewards;
    IPriceSource public priceSource;

    constructor(
        address vaultAddress,
        address supplyAssetAddress,
        address borrowAssetAddress,
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
    {}

    function setWithdrawFee(uint256 fee) public {
        withdrawFee = fee;
    }

    function accumulateInterest(uint256 supplyAmount, uint256 borrowAmount) public {
        totalDeposited += supplyAmount;
        totalBorrowed += borrowAmount;
    }

    function setDepositRewards(uint256 rewards) public {
        depositRewards = rewards;
    }

    function setDepositFee(uint256 depositFeePerc) public {
        depositFee = depositFeePerc;
    }

    function setPriceSource(address oracle) public {
        priceSource = IPriceSource(oracle);
    }

    function _deposit(uint256 amount) internal override {
        totalDeposited += amount - ((amount * depositFee) / 100) + depositRewards;
    }

    function _withdraw(uint256 amount) internal override returns (uint256) {
        if (amount > totalDeposited) {
            amount = totalDeposited;
        }

        totalDeposited -= amount;

        if (withdrawFee > 0) {
            amount -= (amount * withdrawFee) / 1e18;
        }

        IERC20(supplyAsset).transfer(msg.sender, amount);

        return amount;
    }

    function _withdrawAll() internal override {
        IERC20(supplyAsset).transfer(msg.sender, totalDeposited);
        totalDeposited = 0;
    }

    function _borrow(uint256 amount) internal override {
        totalBorrowed += amount;
        mintToken(borrowAsset, address(this), amount);
    }

    function _repay(uint256 amount) internal override {
        if (amount > totalBorrowed) {
            amount = totalBorrowed;
        }
        totalBorrowed -= amount;
    }

    function _recogniseRewardsInBase(address asset) internal override {
        // 100 tokens rewards
        mintToken(asset, address(this), 100 * 10**IERC20Metadata(asset).decimals());
    }

    function setSupplyLoss(
        uint256 supplyLossPerc,
        uint256 borrowLossPerc,
        uint256 feePerc
    ) external {
        feeLoss = (totalDeposited * feePerc) / 100;
        totalDeposited -= (totalDeposited * supplyLossPerc) / 100;
        totalBorrowed -= (totalBorrowed * borrowLossPerc) / 100;
        totalDeposited -= feeLoss;
    }

    function paidLiquidationFee(uint256) public view override returns (uint256) {
        return feeLoss;
    }

    function supplyBalance() public view override returns (uint256) {
        return totalDeposited;
    }

    function borrowBalance() public view override returns (uint256) {
        return totalBorrowed;
    }

    function getInBase(address fromAsset, address toAsset) public view override returns (uint256) {
        return priceSource.getInBase(fromAsset, toAsset); // default returns 1:1 ratio
    }

    function convertToBase(
        uint256 amount,
        address fromAsset,
        address toAsset
    ) external view override returns (uint256) {
        return (getInBase(fromAsset, toAsset) * amount) / 10**IERC20Metadata(fromAsset).decimals();
    }

    function availableBorrowLiquidity() public pure override returns (uint256) {
        return type(uint256).max;
    }

    function getLendingPool() external view override returns (address) {
        return address(this);
    }
}
