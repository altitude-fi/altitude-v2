pragma solidity 0.8.28;

import "../../LenderStrategyUnitTest.sol";
import {Constants} from "../../../../../../scripts/deployer/Constants.sol";
import "../../../../../../contracts/interfaces/external/strategy/lending/Aave/IProtocolDataProvider.sol";
import "../../../../../../contracts/strategies/lending/aave/v3/StrategyAaveV3.sol";
import {BaseGetter} from "../../../../../base/BaseGetter.sol";

contract AaveV3Strategy is LenderStrategyUnitTest {
    StrategyAaveV3 public aaveStrategy;

    function _setUp() internal override {
        vault = makeAddr("Vault");
        borrowAsset = IERC20Metadata(Constants.USDC);
        supplyAsset = IERC20Metadata(Constants.wstETH);

        aaveStrategy = new StrategyAaveV3(
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

    function _priceSupplyInBorrow(uint256 amount) internal view returns (uint256) {
        address[] memory addresses = new address[](2);
        addresses[0] = address(supplyAsset);
        addresses[1] = address(borrowAsset);
        uint256[] memory prices = IPriceOracleGetterV3(Constants.aave_v3_Oracle).getAssetsPrices(addresses);
        return (((prices[0] * (10**borrowAsset.decimals())) / prices[1]) * amount) / 10**supplyAsset.decimals();
    }

    function test_getLendingPool() public view {
        assertEq(aaveStrategy.getLendingPool(), Constants.aave_v3_Pool);
    }

    function test_paidLiquidationFee() public view {
        (, , , uint256 penalty, , , , , , ) = IProtocolDataProvider(Constants.aave_v3_DataProvider)
        .getReserveConfigurationData(address(borrowAsset));
        assertNotEq(penalty, 0);
        uint256 supplyLoss = 10e18;
        assertEq(aaveStrategy.paidLiquidationFee(supplyLoss), supplyLoss - ((supplyLoss * 1e4) / penalty));
    }

    function test_availableBorrowLiquidity() public view {
        (address aToken, , ) = IProtocolDataProvider(Constants.aave_v3_DataProvider).getReserveTokensAddresses(
            address(borrowAsset)
        );

        assertEq(IERC20Metadata(borrowAsset).balanceOf(aToken), aaveStrategy.availableBorrowLiquidity());
    }

    function test_SupplyBalance() public {
        (address aToken, , ) = IProtocolDataProvider(Constants.aave_v3_DataProvider).getReserveTokensAddresses(
            address(supplyAsset)
        );

        uint256 balance = 1000e18;
        vm.mockCall(
            aToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(aaveStrategy)),
            abi.encode(balance)
        );
        assertEq(aaveStrategy.supplyBalance(), balance);

        balance = 6e18;
        vm.mockCall(
            aToken,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(aaveStrategy)),
            abi.encode(balance)
        );
        assertEq(aaveStrategy.supplyBalance(), balance);

        vm.clearMockedCalls();
    }

    function test_BorrowBalance() public {
        (, , address variableDebtTokenAddress) = IProtocolDataProvider(Constants.aave_v3_DataProvider)
        .getReserveTokensAddresses(address(borrowAsset));

        uint256 balance = 1000e18;
        vm.mockCall(
            variableDebtTokenAddress,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(aaveStrategy)),
            abi.encode(balance)
        );
        assertEq(aaveStrategy.borrowBalance(), balance);

        balance = 6e18;
        vm.mockCall(
            variableDebtTokenAddress,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(aaveStrategy)),
            abi.encode(balance)
        );
        assertEq(aaveStrategy.borrowBalance(), balance);

        vm.clearMockedCalls();
    }
}
