// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BaseETH} from "./BaseETH.sol";
import {BaseERC20} from "./BaseERC20.sol";
import {BasePriceSource} from "./BasePriceSource.sol";
import {BaseFarmStrategy} from "./BaseFarmStrategy.sol";
import {BaseSwapStrategy} from "./BaseSwapStrategy.sol";
import {BaseLenderStrategy} from "./BaseLenderStrategy.sol";
import {BaseFlashLoanStrategy} from "./BaseFlashLoanStrategy.sol";

library BaseGetter {
    function getBaseERC20(uint8 decimals) external returns (address) {
        return address(new BaseERC20(decimals, "BaseERC20", "BASE"));
    }

    function getBaseERC20Detailed(uint8 decimals, string memory name, string memory symbol) external returns (address) {
        return address(new BaseERC20(decimals, name, symbol));
    }

    function getBaseETH() external returns (address) {
        return address(new BaseETH());
    }

    function getBaseFarmStrategy(
        address assetAddress,
        address dispatcherAddress,
        address rewardsAddress
    ) external returns (address) {
        return address(new BaseFarmStrategy(assetAddress, dispatcherAddress, rewardsAddress, address(0)));
    }

    function getBaseLenderStrategy(
        address vault,
        address supplyToken,
        address borrowToken,
        address rewardsReceiver,
        address priceSource
    ) external returns (address) {
        BaseLenderStrategy strategy = new BaseLenderStrategy(
            vault,
            supplyToken,
            borrowToken,
            type(uint256).max,
            getBaseSwapStrategy(getBasePriceSource()),
            rewardsReceiver
        );
        strategy.setPriceSource(priceSource);
        return address(strategy);
    }

    function getBaseFlashLoanStrategy() external returns (address) {
        return address(new BaseFlashLoanStrategy());
    }

    function getBasePriceSource() public returns (address) {
        return address(new BasePriceSource());
    }

    function getBaseSwapStrategy(address oracle) public returns (address) {
        return address(new BaseSwapStrategy(oracle));
    }
}
