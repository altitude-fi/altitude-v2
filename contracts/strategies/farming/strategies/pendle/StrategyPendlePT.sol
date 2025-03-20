// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./StrategyPendleBase.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";

/**
 * @title StrategyPendlePT Contract
 * @dev Contract for holding Pendle PT tokens
 * @author Altitude Labs
 **/

contract StrategyPendlePT is StrategyPendleBase {
    constructor(
        address farmDispatcherAddress_,
        address swapStrategy_,
        address router_,
        address routerStatic_,
        address oracle_,
        address market_,
        address farmAsset_,
        uint256 slippage_,
        address rewardsAddress_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_
    )
        StrategyPendleBase(
            farmDispatcherAddress_,
            swapStrategy_,
            router_,
            routerStatic_,
            oracle_,
            market_,
            farmAsset_,
            slippage_,
            rewardsAddress_,
            rewardAssets_,
            nonSkimAssets_
        )
    {}

    /// @notice Acquires Pendle PT tokens
    /// @param amount Amount of asset to deposit
    function _deposit(uint256 amount) internal override {
        if (market.isExpired()) {
            revert PFS_MARKET_EXPIRED();
        }

        amount = _swap(asset, farmAsset, amount);

        uint256 twapRate = oracle.getPtToSyRate(address(market), twapDuration);
        TransferHelper.safeApprove(farmAsset, address(router), amount);
        (uint256 netPtOut, , ) = router.swapExactTokenForPt(
            address(this),
            address(market),
            0,
            _emptyApproxParams(),
            _createTokenInputStruct(amount),
            _emptyLimit()
        );
        _validateRate((amount * 1e18) / twapRate, netPtOut);
    }

    function _exitExpiredMarket() internal returns (bool) {
        if (market.isExpired()) {
            // Exit an expired market
            uint256 ptBalance = PT.balanceOf(address(this));
            if (ptBalance > 0) {
                PT.approve(address(router), ptBalance);
                router.redeemPyToToken(address(this), address(YT), ptBalance, _emptyTokenOutputStruct());
            }

            return true;
        }

        return false;
    }

    /// @notice Sells Pendle PT tokens
    /// @param amountToWithdraw Amount of asset to withdraw
    function _withdraw(uint256 amountToWithdraw) internal override {
        if (!_exitExpiredMarket()) {
            if (farmAsset != asset) {
                // If a conversion is happening, we substitute the requested sum with the
                // input amount we'd need to provide to get it in a swap
                amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountToWithdraw);
            }

            uint256 ptBalance = PT.balanceOf(address(this));

            // amountToWithdraw is going to be reassigned as amount of PT tokens needed to receive requested amount of farm asset
            try routerStatic.swapPtForExactSyStatic(address(market), amountToWithdraw) returns (
                uint256 netPtIn,
                uint256,
                uint256,
                uint256
            ) {
                if (netPtIn > ptBalance) {
                    // If requested amount is more than we have - withdraw all
                    amountToWithdraw = ptBalance;
                } else {
                    amountToWithdraw = netPtIn;
                }
            } catch {
                // The call can revert if there's not enough liquidity
                amountToWithdraw = ptBalance;
            }

            uint256 twapRate = oracle.getPtToSyRate(address(market), twapDuration);
            PT.approve(address(router), amountToWithdraw);
            (uint256 netTokenOut, , ) = router.swapExactPtForToken(
                address(this),
                address(market),
                amountToWithdraw,
                _emptyTokenOutputStruct(),
                _emptyLimit()
            );
            _validateRate((amountToWithdraw * twapRate) / 1e18, netTokenOut);
        }

        // Swap the farm asset to borrow asset (if required)
        _swap(farmAsset, asset, type(uint256).max);
    }

    /// @notice Withdraw the whole balance without slippage checks
    function _emergencyWithdraw() internal override {
        if (_exitExpiredMarket()) {
            return;
        }

        uint256 ptAmount = PT.balanceOf(address(this));
        if (ptAmount > 0) {
            PT.approve(address(router), ptAmount);
            router.swapExactPtForToken(
                address(this),
                address(market),
                ptAmount,
                _emptyTokenOutputStruct(),
                _emptyLimit()
            );
        }
    }

    /// @notice Return farm asset ammount specific for the farm provider
    function _getFarmAssetAmount() internal view virtual override returns (uint256) {
        uint256 ptBalance = PT.balanceOf(address(this));
        if (ptBalance > 0) {
            if (market.isExpired()) {
                ptBalance = routerStatic.redeemPyToTokenStatic(address(YT), ptBalance, farmAsset);
            } else {
                (ptBalance, , , , ) = routerStatic.swapExactPtForTokenStatic(address(market), ptBalance, farmAsset);
            }
        }

        return ptBalance;
    }
}
