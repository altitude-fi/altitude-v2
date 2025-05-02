// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IFarmStrategy.sol";

import "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "@pendle/core-v2/contracts/interfaces/IPPYLpOracle.sol";
import "@pendle/core-v2/contracts/interfaces/IPRouterStatic.sol";

/**
 * @author Altitude Protocol
 **/

interface IPendleFarmStrategy is IFarmStrategy {
    function router() external view returns (IPAllActionV3);

    function routerStatic() external view returns (IPRouterStatic);

    function oracle() external view returns (IPPYLpOracle);

    function market() external view returns (IPMarket);

    function SY() external view returns (IStandardizedYield);

    function PT() external view returns (IPPrincipalToken);

    function YT() external view returns (IPYieldToken);

    function rewardAssets(uint256) external view returns (address);

    function SLIPPAGE_BASE() external view returns (uint256);

    function slippage() external view returns (uint256);

    function twapDuration() external view returns (uint32);

    event SetRewardAssets(address[] oldAssets, address[] newAssets);
    event SetTwapDuration(uint32 oldDuration, uint32 newDuration);
    event SetSlippage(uint256 oldSlippage, uint256 newSlippage);

    error PFS_ORACLE_CARDINALITY(uint16 cardinalityRequired);
    error PFS_ORACLE_UNPOPULATED();
    error PFS_SLIPPAGE(uint256 twapRate, uint256 currentRate);
    error PFS_MARKET_EXPIRED();

    function setRewardAssets(address[] memory rewardAssets_) external;

    function setTwapDuration(uint32 twapDuration_) external;

    function setSlippage(uint256 slippage_) external;
}
