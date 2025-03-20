// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./IFarmStrategy.sol";
import "../../../external/strategy/farming/Convex/IConvex.sol";
import "../../../external/strategy/farming/Convex/ICVXRewards.sol";

/**
 * @author Altitude Protocol
 **/

interface IConvexFarmStrategy is IFarmStrategy {
    struct Config {
        address curvePool;
        address curveLP;
        address zapPool;
        address convex;
        uint256 convexPoolID;
        address cvx;
        address crv;
        address crvRewards;
        uint128 assetIndex;
        address swapStrategy;
        uint256 slippage;
        uint256 referencePrice;
        address farmAsset;
    }

    event SetToClaimExtraRewards(bool toClaim);
    event SetSlippage(uint256 oldSlippage, uint256 newSlippage);
    event SetReferencePrice(uint256 oldPrice, uint256 newPrice);
    event OracleFeedError(address token);

    // Convex Farm Strategy Errors
    error CFS_OUT_OF_BOUNDS();

    function curvePool() external view returns (address);

    function curveLP() external view returns (IERC20Metadata);

    function crvDecimals() external view returns (uint256);

    function zapPool() external view returns (address);

    function convex() external view returns (IConvex);

    function convexPoolID() external view returns (uint256);

    function cvx() external view returns (IERC20);

    function crv() external view returns (IERC20);

    function crvRewards() external view returns (ICVXRewards);

    function assetIndex() external view returns (uint128);

    function farmAssetDecimals() external view returns (uint8);

    function SLIPPAGE_BASE() external view returns (uint256);

    function slippage() external view returns (uint256);

    function referencePrice() external view returns (uint256);

    function setToClaimExtraRewards(bool toClaim_) external;

    function setSlippage(uint256 slippage_) external;

    function setReferencePrice(uint256 price_) external;

    function toClaimExtra() external view returns (bool);
}
