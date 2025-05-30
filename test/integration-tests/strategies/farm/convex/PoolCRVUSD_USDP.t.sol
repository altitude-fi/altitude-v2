// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {StrategyStable2Pool} from "../../../../../contracts/strategies/farming/strategies/convex/StrategyStable2Pool.sol";
import {ICurve2} from "../../../../../contracts/interfaces/external/strategy/farming/Curve/ICurve2.sol";
import {IConvexFarmStrategy} from "../../../../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";
import {ConvexStrategy} from "./ConvexStrategy.sol";

contract PoolCRVUSD_USDP is ConvexStrategy {
    using stdStorage for StdStorage;

    function _setUp() internal override {
        DEPOSIT = 100e6;
        FEE_TOLERANCE = 1e16; // 1% fee acceptable

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(Constants.crvUSD);
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        IConvexFarmStrategy.Config memory config = IConvexFarmStrategy.Config(
            Constants.curve_Pool_crvUSD_USDP,
            Constants.curve_Pool_crvUSD_USDP,
            Constants.curve_Pool_crvUSD_USDP,
            Constants.convex_Booster, // convex
            180, // convex pid
            0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93,
            1,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            5000, // 0.5% slippage
            ICurve2(Constants.curve_Pool_crvUSD_USDP).get_virtual_price(),
            Constants.crvUSD
        );

        address[] memory rewardAssets = new address[](2);
        rewardAssets[0] = Constants.CVX;
        rewardAssets[1] = Constants.CRV;

        farmStrategy = new StrategyStable2Pool(dispatcher, dispatcher, rewardAssets, config);
    }
}
