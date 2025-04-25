// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {StrategyStableNGPool} from "../../../../../contracts/strategies/farming/strategies/convex/StrategyStableNGPool.sol";
import {ICurveNG} from "../../../../../contracts/interfaces/external/strategy/farming/Curve/ICurveNG.sol";
import {IConvexFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";
import {ConvexStrategy} from "./ConvexStrategy.sol";

contract PoolCRVUSD_StableNG is ConvexStrategy {
    using stdStorage for StdStorage;

    function _setUp() internal override {
        DEPOSIT = 1e6;
        FEE_TOLERANCE = 1e16; // 1% fee acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.crvUSD);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        IConvexFarmStrategy.Config memory config = IConvexFarmStrategy.Config(
            Constants.curve_Pool_pyUSD_crvUSD,
            Constants.curve_Pool_pyUSD_crvUSD,
            Constants.curve_Pool_pyUSD_crvUSD,
            Constants.convex_Booster, // convex
            289, // convex pid
            Constants.CVX,
            Constants.CRV,
            0x79579633029a61963eDfbA1C0BE22498b6e0D33D,
            1,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            5000, // 0.5% slippage
            ICurveNG(Constants.curve_Pool_pyUSD_crvUSD).get_virtual_price(),
            Constants.crvUSD
        );

        farmStrategy = new StrategyStableNGPool(dispatcher, dispatcher, config);
    }
}
