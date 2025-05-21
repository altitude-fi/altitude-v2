// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {ICurve} from "../../../../../contracts/interfaces/external/strategy/farming/Curve/ICurve.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {StrategyMeta3Pool} from "../../../../../contracts/strategies/farming/strategies/convex/StrategyMeta3Pool.sol";
import {IConvexFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";
import {ConvexStrategy} from "./ConvexStrategy.sol";

contract Pool3CRV_USDV is ConvexStrategy {
    using stdStorage for StdStorage;

    function _setUp() internal override {
        DEPOSIT = 1e6;
        FEE_TOLERANCE = 1e16; // 1% fee acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.USDC);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        IConvexFarmStrategy.Config memory config = IConvexFarmStrategy.Config(
            Constants.curve_Pool_USDV_3crv,
            Constants.curve_Pool_USDV_3crv,
            Constants.curve_MIMZap,
            Constants.convex_Booster, // convex
            290, // convex pid
            0x437BdEa046406130646E67514eed0aC965692963,
            2,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            5000, // 0.5% slippage
            ICurve(Constants.curve_Pool_USDV_3crv).get_virtual_price(),
            Constants.USDC
        );

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = Constants.CVX;
        rewardAssets[1] = Constants.CRV;

        farmStrategy = new StrategyMeta3Pool(dispatcher, dispatcher, rewardAssets, config);
    }
}
