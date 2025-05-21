// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {StrategyMeta3Pool} from "../../../../../contracts/strategies/farming/strategies/convex/StrategyMeta3Pool.sol";
import {ICurve} from "../../../../../contracts/interfaces/external/strategy/farming/Curve/ICurve.sol";
import {IConvexFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";
import {ConvexStrategy} from "./ConvexStrategy.sol";

contract PoolMIM_USDC is ConvexStrategy {
    using stdStorage for StdStorage;

    function _setUp() internal override {
        DEPOSIT = 1000e6;
        FEE_TOLERANCE = 1e16; // 1% fee acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.USDC);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        IConvexFarmStrategy.Config memory config = IConvexFarmStrategy.Config(
            Constants.curve_Pool_MIM,
            Constants.curve_MIMTokens()[0],
            Constants.curve_MIMZap,
            Constants.convex_Booster, // convex
            40, // convex pid
            Constants.convex_RewardsToken_MIM_CRV,
            2,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            10000, // 1% slippage
            ICurve(Constants.curve_Pool_MIM).get_virtual_price(),
            Constants.USDC
        );

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = Constants.CVX;
        rewardAssets[1] = Constants.CRV;

        farmStrategy = new StrategyMeta3Pool(dispatcher, dispatcher, rewardAssets, config);
    }
}
