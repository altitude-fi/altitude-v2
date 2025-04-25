// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {StrategyMetaPool} from "../../../../../contracts/strategies/farming/strategies/convex/StrategyMetaPool.sol";
import {ICurve4} from "../../../../../contracts/interfaces/external/strategy/farming/Curve/ICurve4.sol";
import {IConvexFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";
import {ConvexStrategy} from "./ConvexStrategy.sol";

contract PoolMUSD is ConvexStrategy {
    using stdStorage for StdStorage;

    function _setUp() internal override {
        DEPOSIT = 1000e6;
        FEE_TOLERANCE = 1e16; // 1% fee acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.USDC);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        IConvexFarmStrategy.Config memory config = IConvexFarmStrategy.Config(
            Constants.curve_Pool_mUSD,
            Constants.mUSD,
            Constants.curve_MUSDZap,
            Constants.convex_Booster, // convex
            14, // convex pid
            Constants.CVX,
            Constants.CRV,
            Constants.convex_RewardsToken_mUSD_CRV,
            2,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            5000, // 0.5% slippage
            ICurve4(Constants.curve_Pool_mUSD).get_virtual_price(),
            Constants.USDC
        );

        farmStrategy = new StrategyMetaPool(dispatcher, dispatcher, config);
    }
}
