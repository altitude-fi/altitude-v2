pragma solidity 0.8.28;

import "../LenderStrategyIntegrationTest.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import "../../../../../contracts/interfaces/external/strategy/lending/Aave/IProtocolDataProvider.sol";
import "../../../../../contracts/strategies/lending/aave/v3/StrategyAaveV3.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";

contract AaveV3Strategy is LenderStrategyIntegrationTest {
    StrategyAaveV3 public aaveStrategy;

    function _setUp() internal override {
        vault = makeAddr("Vault");
        borrowAsset = IERC20Metadata(Constants.USDC);
        supplyAsset = IERC20Metadata(Constants.wstETH);

        lenderStrategy = aaveStrategy = new StrategyAaveV3(
            vault,
            address(supplyAsset),
            address(borrowAsset),
            Constants.aave_v3_Pool,
            Constants.aave_v3_Provider,
            Constants.aave_v3_DataProvider,
            Constants.aave_v3_IncentivesController,
            MAX_DEPOSIT_FEE,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            vault
        );

        DEPOSIT = 10e18;
        BORROW = (_priceSupplyInBorrow(DEPOSIT) * 50) / 100; // 50% of the supply value
    }

    function _priceSupplyInBorrow(uint256 amount) internal view override returns (uint256) {
        address[] memory addresses = new address[](2);
        addresses[0] = address(supplyAsset);
        addresses[1] = address(borrowAsset);
        uint256[] memory prices = IPriceOracleGetterV3(Constants.aave_v3_Oracle).getAssetsPrices(addresses);

        assertNotEq(prices[0], 0);
        assertNotEq(prices[1], 0);

        return (((prices[0] * (10 ** borrowAsset.decimals())) / prices[1]) * amount) / 10 ** supplyAsset.decimals();
    }

    function _accumulateRewards(address[] memory rewardsList) internal virtual override {
        address[] memory addresses = new address[](2);
        (addresses[0], , ) = IProtocolDataProvider(Constants.aave_v3_DataProvider).getReserveTokensAddresses(
            address(supplyAsset)
        );
        (, , addresses[1]) = IProtocolDataProvider(Constants.aave_v3_DataProvider).getReserveTokensAddresses(
            address(borrowAsset)
        );

        uint256[] memory claimedAmounts = new uint256[](rewardsList.length);

        for (uint256 i = 0; i < rewardsList.length; i++) {
            claimedAmounts[i] = 100 * 10 ** IERC20Metadata(rewardsList[i]).decimals();
            mintToken(rewardsList[i], address(aaveStrategy), claimedAmounts[i]);
        }
        vm.mockCall(
            Constants.aave_v3_IncentivesController,
            abi.encodeWithSelector(IRewardsController.claimAllRewardsToSelf.selector, addresses),
            abi.encode(rewardsList, claimedAmounts)
        );
    }
}
