// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import {TokensGenerator} from "../utils/TokensGenerator.sol";
import "../../contracts/strategies/farming/strategies/convex/StrategyGenericPool.sol";
import "../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";

contract BaseConvexStrategy is StrategyGenericPool, TokensGenerator {
    constructor(
        address farmDispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        IConvexFarmStrategy.Config memory config
    ) StrategyGenericPool(farmDispatcherAddress, rewardsAddress, rewardAssets_, config) {}

    function _curveDeposit(uint256 toDeposit, uint256 minLPOut) internal override {
        // Remove the tokens from the balance
        burnToken(farmAsset, address(this), toDeposit);
        // Mints in return LP tokens
        mintToken(address(curveLP), address(this), minLPOut);
    }

    function _underlyingFromLP(uint256 amount) internal view override returns (uint256) {
        // 1:1 ratio
        uint256 fromDecimals = IToken(address(crvRewards)).decimals();
        uint256 toDecimals = IToken(asset).decimals();
        return (amount * 10 ** toDecimals) / 10 ** fromDecimals;
    }

    function _curveWithdraw(uint256 lpAmount, uint256 minAssetOut) internal override {
        burnToken(address(curveLP), address(this), lpAmount);
        mintToken(farmAsset, address(this), minAssetOut);
    }

    function _curveEmergencyWithdraw(uint256 lpAmount) internal virtual override {
        // 1:1 ratio
        uint256 fromDecimals = IToken(address(curveLP)).decimals();
        uint256 toDecimals = IToken(asset).decimals();
        uint256 amountOut = (lpAmount * 10 ** toDecimals) / 10 ** fromDecimals;

        burnToken(address(curveLP), address(this), lpAmount);
        mintToken(farmAsset, address(this), amountOut);
    }

    function exactLP(uint256 amount) public view returns (uint256) {
        return _calcExactLP(amount);
    }

    function lpExpected(uint256 amount) public view returns (uint256) {
        return calcLPExpected(amount);
    }

    function underlyingExpected(uint256 amount) public view returns (uint256) {
        return calcUnderlyingExpected(amount);
    }
}
