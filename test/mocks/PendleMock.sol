// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import {TokensGenerator} from "../utils/TokensGenerator.sol";
import "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../contracts/libraries/utils/Utils.sol";

contract RouterMock is TokensGenerator {
    address public asset;

    constructor(address farmAsset) {
        asset = farmAsset;
    }

    function addLiquiditySingleTokenKeepYt(
        address receiver,
        address market,
        uint256,
        uint256,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netYtOut, uint256 netSyMintPy, uint256 netSyInterm) {
        netYtOut = input.netTokenIn / 2;
        netLpOut = input.netTokenIn / 2;

        netSyInterm = input.netTokenIn;
        netSyMintPy = 0;

        burnToken(input.tokenIn, msg.sender, input.netTokenIn);
        mintToken(address(MarketMock(market).YT()), receiver, netYtOut);
        mintToken(address(market), receiver, netLpOut);
    }

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        netTokenOut = netLpToRemove;
        netSyInterm = netLpToRemove;
        netSyFee = 0;

        burnToken(address(market), msg.sender, netLpToRemove);
        mintToken(output.tokenOut, receiver, netTokenOut);
    }

    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256,
        ApproxParams calldata,
        TokenInput calldata input,
        LimitOrderData calldata
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm) {
        burnToken(input.tokenIn, msg.sender, input.netTokenIn);
        mintToken(address(MarketMock(market).PT()), receiver, input.netTokenIn);
        return (input.netTokenIn, 0, input.netTokenIn);
    }

    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        burnToken(address(MarketMock(market).PT()), msg.sender, exactPtIn);
        mintToken(output.tokenOut, receiver, exactPtIn);
        return (exactPtIn, 0, exactPtIn);
    }

    function swapExactYtForToken(
        address receiver,
        address market,
        uint256 exactYtIn,
        TokenOutput calldata output,
        LimitOrderData calldata
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm) {
        burnToken(address(MarketMock(market).YT()), msg.sender, exactYtIn);
        mintToken(output.tokenOut, receiver, exactYtIn);
        return (exactYtIn, 0, exactYtIn);
    }
}

contract RouterStaticMock is TokensGenerator {
    address public immutable asset;
    uint8 public immutable decimals;

    constructor(address farmAsset) {
        asset = farmAsset;
        decimals = ERC20(farmAsset).decimals();
    }

    function swapExactPtForTokenStatic(
        address, // market,
        uint256 exactPtIn,
        address // tokenOut
    ) public pure returns (uint256, uint256, uint256, uint256, uint256) {
        return (exactPtIn, 0, 0, 0, 0);
    }

    function redeemPyToTokenStatic(
        address, // YT,
        uint256 netPYToRedeem,
        address // tokenOut
    ) external pure returns (uint256 netTokenOut) {
        netTokenOut = netPYToRedeem;
    }

    /// @dev netPtIn is the parameter to approx
    function swapPtForExactSyStatic(
        address, // market,
        uint256 exactSyOut
    ) public pure returns (uint256, uint256, uint256, uint256) {
        return (exactSyOut, 0, 0, 0);
    }

    function removeLiquiditySingleTokenStatic(
        address, //market,
        uint256 netLpToRemove,
        address //tokenOut
    ) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (Utils.scaleAmount(netLpToRemove, 18, decimals), 0, 0, 0, 0, 0, 0, 0);
    }

    function swapYtForExactSyStatic(
        address, // market,
        uint256 exactSyOut
    ) public pure returns (uint256, uint256, uint256, uint256) {
        return (exactSyOut, 0, 0, 0);
    }

    function swapExactYtForTokenStatic(
        address, //market,
        uint256 exactYtIn,
        address //tokenOut
    ) public pure returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (exactYtIn, 0, 0, 0, 0, 0, 0, 0);
    }
}

contract MarketMock is ERC20("Token", "TKN") {
    address public asset;
    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;
    bool public isExpired;

    constructor(address asset_, address SY_, address PT_, address YT_) {
        asset = asset_;
        SY = IStandardizedYield(SY_);
        PT = IPPrincipalToken(PT_);
        YT = IPYieldToken(YT_);
    }

    function readTokens() external view returns (IStandardizedYield, IPPrincipalToken, IPYieldToken) {
        return (SY, PT, YT);
    }
}

contract OracleMock {
    address public asset;

    constructor(address farmAsset) {
        asset = farmAsset;
    }

    function getPtToSyRate(address market, uint32) external view returns (uint256) {
        return 1 * 10 ** MarketMock(market).SY().decimals();
    }

    function getLpToSyRate(address market, uint32) external view returns (uint256) {
        return 1 * 10 ** MarketMock(market).SY().decimals();
    }

    function getYtToSyRate(address market, uint32) external view returns (uint256) {
        return 1 * 10 ** MarketMock(market).SY().decimals();
    }

    function getOracleState(
        address,
        uint32
    )
        external
        pure
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied)
    {
        return (false, 0, true);
    }
}
