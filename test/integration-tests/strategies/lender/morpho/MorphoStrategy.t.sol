// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../LenderStrategyIntegrationTest.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import "../../../../../contracts/strategies/lending/morpho/StrategyMorphoV1.sol";
import "../../../../../contracts/interfaces/internal/strategy/lending/IMorphoStrategy.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";
import {IOracle} from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";
import {Id} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

contract MorphoStrategy is LenderStrategyIntegrationTest {
    StrategyMorphoV1 public morphoStrategy;

    function _setUp() internal override {
        vault = makeAddr("Vault");
        borrowAsset = IERC20Metadata(Constants.USDC);
        supplyAsset = IERC20Metadata(Constants.wstETH);

        Id marketId;
        bytes32 morpho_Market_WSTETH_USDC = Constants.morpho_Market_WSTETH_USDC;
        assembly {
            marketId := morpho_Market_WSTETH_USDC
        }

        lenderStrategy = morphoStrategy = new StrategyMorphoV1(
            vault,
            address(supplyAsset),
            address(borrowAsset),
            Constants.morpho_Pool,
            marketId,
            MAX_DEPOSIT_FEE,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            vault,
            new address[](0)
        );

        DEPOSIT = 10e18;
        BORROW = (_priceSupplyInBorrow(DEPOSIT) * 50) / 100; // 50% of the supply value
    }

    function _priceSupplyInBorrow(uint256 amount) internal view override returns (uint256) {
        uint256 price = IOracle(morphoStrategy.marketOracle()).price();
        assertNotEq(price, 0);

        uint8 oraclePriceDecimals = 36 + borrowAsset.decimals() - supplyAsset.decimals();

        price = Utils.scaleAmount(price, oraclePriceDecimals, IERC20Metadata(borrowAsset).decimals());

        return (amount * price) / 10 ** supplyAsset.decimals();
    }

    function _accumulateRewards(address[] memory rewardsList) internal virtual override {
        morphoStrategy.setRewardAssets(rewardsList);

        uint256[] memory claimedAmounts = new uint256[](rewardsList.length);

        for (uint256 i = 0; i < rewardsList.length; i++) {
            claimedAmounts[i] = 100 * 10 ** IERC20Metadata(rewardsList[i]).decimals();
            mintToken(rewardsList[i], address(morphoStrategy), claimedAmounts[i]);
        }
    }

    function test_invalidMarket() public {
        Id marketId;

        bytes32 morpho_Market_WSTETH_USDC = 0x84662b4f95b85d6b082b68d32cf71bb565b3f22f216a65509cc2ede7dccdfe8c;
        assembly {
            marketId := morpho_Market_WSTETH_USDC
        }
        address swapStrategy = BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource());

        vm.expectRevert(IMorphoStrategy.SM_INVALID_MARKET.selector);
        new StrategyMorphoV1(
            vault,
            address(supplyAsset),
            address(borrowAsset),
            Constants.morpho_Pool,
            marketId,
            MAX_DEPOSIT_FEE,
            swapStrategy,
            vault,
            new address[](0)
        );
    }

    function test_availableBorrowLiquidityEdge() public {
        // pool token balance less than available borrow
        uint256 before = lenderStrategy.availableBorrowLiquidity();
        uint256 poolBalance = borrowAsset.balanceOf(Constants.morpho_Pool);
        burnToken(address(borrowAsset), Constants.morpho_Pool, poolBalance - before + 1);

        assertGt(before, lenderStrategy.availableBorrowLiquidity());
    }
}
