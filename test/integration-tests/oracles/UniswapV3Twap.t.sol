// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../ForkTest.sol";
import "forge-std/console.sol";
import {Constants} from "../../../scripts/deployer/Constants.sol";
import {UniswapV3Twap} from "../../../contracts/oracles/UniswapV3Twap.sol";
import {UniswapV3Strategy, SwapRoutes} from "../../utils/SwapRoutes.sol";

contract UniswapV3TwapTest is ForkTest {
    UniswapV3Twap public uniswapTwap;

    address immutable someUser = makeAddr("someUser");

    function setUp() public override {
        super.setUp();
        vm.rollFork(20000000);

        uniswapTwap = new UniswapV3Twap(Constants.uniswap_v3_Factory, 1 hours);
    }

    function test_CorrectDeployment() public view {
        assertEq(uniswapTwap.factory(), Constants.uniswap_v3_Factory);
        assertEq(uniswapTwap.TWAP_INTERVAL(), 1 hours);
    }

    function test_RevertDeploymentWithInvalidInterval() public {
        vm.expectRevert(UniswapV3Twap.UV3_TWAP_ZERO_TIME_INTERVAL.selector);
        new UniswapV3Twap(Constants.uniswap_v3_Factory, 0);
    }

    function test_setTwapInterval() public {
        vm.expectRevert(UniswapV3Twap.UV3_TWAP_ZERO_TIME_INTERVAL.selector);
        uniswapTwap.setTwapInterval(0);

        assertNotEq(uniswapTwap.TWAP_INTERVAL(), 15 minutes);
        uniswapTwap.setTwapInterval(15 minutes);
        assertEq(uniswapTwap.TWAP_INTERVAL(), 15 minutes);

        vm.prank(someUser);
        vm.expectRevert("Ownable: caller is not the owner");
        uniswapTwap.setTwapInterval(15 minutes);
    }

    function test_setOraclePair() public {
        // set pair
        UniswapV3Strategy.SwapRoute[] memory path = SwapRoutes.get_UniswapDAIToWBTC();
        UniswapV3Twap.PairRoute[] memory pairRoutes = new UniswapV3Twap.PairRoute[](path.length);
        assembly {
            pairRoutes := path
        }
        uniswapTwap.setOraclePair(Constants.DAI, Constants.WBTC, pairRoutes);

        // check pair
        uint24 feeTier;
        address assetTo;
        for (uint256 i; i < path.length; i++) {
            (feeTier, assetTo) = uniswapTwap.oraclePairs(Constants.DAI, Constants.WBTC, i);
            assertEq(feeTier, path[i].feeTier);
            assertEq(assetTo, path[i].assetTo);
        }

        // delete pair
        uniswapTwap.setOraclePair(Constants.DAI, Constants.WBTC, new UniswapV3Twap.PairRoute[](0));
        vm.expectRevert();
        (feeTier, assetTo) = uniswapTwap.oraclePairs(Constants.DAI, Constants.WBTC, 0);
    }

    function test_setOraclePairReverts() public {
        UniswapV3Strategy.SwapRoute[] memory path = SwapRoutes.get_UniswapDAIToWBTC();
        UniswapV3Twap.PairRoute[] memory pairRoutes = new UniswapV3Twap.PairRoute[](path.length);
        assembly {
            pairRoutes := path
        }
        vm.prank(someUser);
        vm.expectRevert("Ownable: caller is not the owner");
        uniswapTwap.setOraclePair(Constants.DAI, Constants.USDC, pairRoutes);

        vm.expectRevert(UniswapV3Twap.UV3_TWAP_INVALID_DESTINATION.selector);
        uniswapTwap.setOraclePair(Constants.DAI, Constants.USDC, pairRoutes);

        pairRoutes[0].feeTier = 123;
        vm.expectRevert(UniswapV3Twap.UV3_TWAP_INVALID_FEE.selector);
        uniswapTwap.setOraclePair(Constants.DAI, Constants.WBTC, pairRoutes);
    }

    function test_getInUSD() public {
        // this function is not implemented for this strategy and should revert
        vm.expectRevert(UniswapV3Twap.UV3_TWAP_PAIR_DOES_NOT_EXISTS.selector);
        uniswapTwap.getInUSD(address(0));
    }

    function test_getInBase() public {
        // set pair
        UniswapV3Strategy.SwapRoute[] memory path = SwapRoutes.get_UniswapDAIToWBTC();
        UniswapV3Twap.PairRoute[] memory pairRoutes = new UniswapV3Twap.PairRoute[](path.length);
        assembly {
            pairRoutes := path
        }
        uniswapTwap.setOraclePair(Constants.DAI, Constants.WBTC, pairRoutes);

        uint256 ratio = uniswapTwap.getInBase(Constants.DAI, Constants.WBTC);
        // 1 dai is 0.00001475 wBTC at block 20000000
        assertEq(ratio, 1475);
    }

    function test_getInBaseReverts() public {
        vm.expectRevert(UniswapV3Twap.UV3_TWAP_PAIR_DOES_NOT_EXISTS.selector);
        uniswapTwap.getInBase(Constants.DAI, Constants.WBTC);
    }
}
