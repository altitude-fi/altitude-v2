// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./StrategyPendleBase.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import "../../../../libraries/utils/Utils.sol";

/**
 * @title StrategyPendleLP Contract
 * @dev Contract for providing liquidity to a Pendle market
 * @author Altitude Labs
 **/

contract StrategyPendleLP is StrategyPendleBase {
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

    /// @notice Provide liquidity to Pendle market
    /// @param amount Amount of asset to deposit
    function _deposit(uint256 amount) internal override {
        if (market.isExpired()) {
            revert PFS_MARKET_EXPIRED();
        }

        uint256 twapLpRate = oracle.getLpToSyRate(address(market), twapDuration);
        uint256 twapYtRate = oracle.getYtToSyRate(address(market), twapDuration);
        amount = _swap(asset, farmAsset, amount);

        TransferHelper.safeApprove(farmAsset, address(router), amount);
        (uint256 netLpOut, uint256 netYtOut, , ) = router.addLiquiditySingleTokenKeepYt(
            address(this),
            address(market),
            0,
            0,
            _createTokenInputStruct(amount)
        );

        uint256 outputWorth = Utils.scaleAmount(netLpOut * twapLpRate, 36, SY_DECIMALS) +
            ((netYtOut * twapYtRate) / 1e18);

        _validateRate(amount, outputWorth);
    }

    /// @notice Redeem LP tokens from Pendle market
    /// @param amountToWithdraw Amount of asset to withdraw
    function _withdraw(uint256 amountToWithdraw) internal override {
        if (farmAsset != asset) {
            // If a conversion is happening, we substitute the requested sum with the
            // input amount  of `farmAsset` we'd need to provide to get it in a swap
            amountToWithdraw = swapStrategy.getAmountIn(farmAsset, asset, amountToWithdraw);
        }
        uint256 farmAssetWant = amountToWithdraw;

        uint256 lpBalance = market.balanceOf(address(this));
        if (lpBalance > 0) {
            // Value if we remove all of our LP
            (uint256 farmBalance, , , , , , , ) = routerStatic.removeLiquiditySingleTokenStatic(
                address(market),
                lpBalance,
                farmAsset
            );

            // amountToWithdraw is going to be reassigned as amount of LP tokens needed to receive requested amount of farm asset
            if (amountToWithdraw >= farmBalance || market.isExpired()) {
                // Requested amount is more than we have, or market is past maturity date - withdraw all
                amountToWithdraw = lpBalance;
            } else {
                // Determine LP needed by proportion
                amountToWithdraw = (lpBalance * (((amountToWithdraw * 1e18) / farmBalance) + 1)) / 1e18;
            }

            uint256 twapLpRate = oracle.getLpToSyRate(address(market), twapDuration);
            uint256 netTokenOut = _withdrawLP(amountToWithdraw);
            _validateRate(Utils.scaleAmount(amountToWithdraw * twapLpRate, 36, SY_DECIMALS), netTokenOut);

            /// @dev amountToWithdraw is being reassigned in farmAsset token
            amountToWithdraw = Utils.subOrZero(farmAssetWant, netTokenOut);
        }

        if (amountToWithdraw > 0 && !market.isExpired()) {
            // We didn't satisfy the withdraw with LP tokens, so we try to sell YT tokens
            /// @dev Rarely executed branch. YT has no value past expiry.
            uint256 ytBalance = YT.balanceOf(address(this));

            if (ytBalance > 0) {
                // amountToWithdraw is reassigned as amount of YT tokens needed to receive requested amount of farm asset
                try routerStatic.swapYtForExactSyStatic(address(market), amountToWithdraw) returns (
                    uint256 netYtIn,
                    uint256,
                    uint256,
                    uint256
                ) {
                    if (netYtIn > ytBalance) {
                        // If requested amount is more than we have - withdraw all
                        amountToWithdraw = ytBalance;
                    } else {
                        amountToWithdraw = netYtIn;
                    }
                } catch {
                    /// @dev `amountToWithdraw` coming from FarmDispatcher is not tied to our or the pool's balance
                    /// and the call can revert if there's not enough liquidity.
                    amountToWithdraw = ytBalance;
                }

                uint256 twapYtRate = oracle.getYtToSyRate(address(market), twapDuration);
                uint256 netTokenOut = _withdrawYT(amountToWithdraw);
                _validateRate((amountToWithdraw * twapYtRate) / 1e18, netTokenOut);
            }
        }

        // Will swap the farm asset to borrow asset if needed
        _swap(farmAsset, asset, type(uint256).max);
    }

    function _withdrawYT(uint256 amount) internal returns (uint256 netTokenOut) {
        if (amount > 0) {
            YT.approve(address(router), amount);
            (netTokenOut, , ) = router.swapExactYtForToken(
                address(this),
                address(market),
                amount,
                _emptyTokenOutputStruct(),
                _emptyLimit()
            );
        }
    }

    function _withdrawLP(uint256 amount) internal returns (uint256 netTokenOut) {
        if (amount > 0) {
            market.approve(address(router), amount);
            (netTokenOut, , ) = router.removeLiquiditySingleToken(
                address(this),
                address(market),
                amount,
                _emptyTokenOutputStruct(),
                _emptyLimit()
            );
        }
    }

    /// @notice Withdraw the whole balance without slippage checks
    function _emergencyWithdraw() internal override {
        _withdrawLP(market.balanceOf(address(this)));
        _withdrawYT(YT.balanceOf(address(this)));
    }

    /// @notice Return total balance in farmAsset
    function _getFarmAssetAmount() internal view virtual override returns (uint256) {
        uint256 lpBalance = market.balanceOf(address(this));
        if (lpBalance > 0) {
            (lpBalance, , , , , , , ) = routerStatic.removeLiquiditySingleTokenStatic(
                address(market),
                lpBalance,
                farmAsset
            );
        }

        uint256 ytBalance;
        if (!market.isExpired()) {
            ytBalance = YT.balanceOf(address(this));

            if (ytBalance > 0) {
                (ytBalance, , , , , , , ) = routerStatic.swapExactYtForTokenStatic(
                    address(market),
                    ytBalance,
                    farmAsset
                );
            }
        }

        return lpBalance + ytBalance;
    }
}
