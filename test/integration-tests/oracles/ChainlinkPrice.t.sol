// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../../ForkTest.sol";

import {Constants} from "../../../scripts/deployer/Constants.sol";
import {ChainlinkPrice} from "../../../contracts/oracles/ChainlinkPrice.sol";
import {IChainlinkPrice} from "../../../contracts/interfaces/internal/oracles/IChainlinkPrice.sol";

import {FeedRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

contract ChainlinkPriceTest is ForkTest {
    ChainlinkPrice public chainlinkPrice;
    address public constant FEED_REGISTRY = Constants.chainlink_FeedRegistry;

    // Test tokens
    address public constant AAVE = Constants.aave_v2_Token;
    address public constant WETH = Constants.WETH;
    address public constant WBTC = Constants.WBTC;
    address public constant DAI = Constants.DAI;
    address public constant USDC = Constants.USDC;
    address public constant WSTETH = Constants.wstETH;

    function setUp() public override {
        super.setUp();

        address[] memory fromAsset = new address[](2);
        fromAsset[0] = WBTC;
        fromAsset[1] = WETH;

        address[] memory toAsset = new address[](2);
        toAsset[0] = Constants.chainlink_BTC;
        toAsset[1] = Constants.chainlink_ETH;

        chainlinkPrice = new ChainlinkPrice(
            FeedRegistryInterface(FEED_REGISTRY),
            fromAsset,
            toAsset,
            Constants.chainlink_USD,
            2 days
        );
    }

    function test_CorrectDeployment() public view {
        assertEq(address(chainlinkPrice.FEED_REGISTRY()), FEED_REGISTRY);
        assertEq(chainlinkPrice.LINKING_DENOMINATION(), Constants.chainlink_USD);
        assertEq(chainlinkPrice.STALE_DATA_SECONDS(), 2 days);
        assertEq(chainlinkPrice.assetMap(WBTC), Constants.chainlink_BTC);
        assertEq(chainlinkPrice.assetMap(WETH), Constants.chainlink_ETH);
    }

    function test_RevertDeploymentWithInvalidAssetMap() public {
        address[] memory fromAsset = new address[](2);
        fromAsset[0] = WBTC;
        fromAsset[1] = WETH;

        address[] memory toAsset = new address[](1);
        toAsset[0] = Constants.chainlink_BTC;

        vm.expectRevert(IChainlinkPrice.CL_PRICE_INVALID_ASSET_MAP.selector);
        new ChainlinkPrice(FeedRegistryInterface(FEED_REGISTRY), fromAsset, toAsset, Constants.chainlink_USD, 2 days);
    }

    function test_AddAssetMap() public {
        address assetFrom = makeAddr("assetFrom");
        address assetTo = makeAddr("assetTo");

        chainlinkPrice.addAssetMap(assetFrom, assetTo);
        assertEq(chainlinkPrice.assetMap(assetFrom), assetTo);
    }

    function test_RevertAddAssetMapUnauthorized() public {
        address assetFrom = makeAddr("assetFrom");
        address assetTo = makeAddr("assetTo");

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        chainlinkPrice.addAssetMap(assetFrom, assetTo);
    }

    function test_RevertAddExistingAssetMap() public {
        vm.expectRevert(IChainlinkPrice.CL_CAN_NOT_EXISTING_ASSET_MAP.selector);
        chainlinkPrice.addAssetMap(WBTC, Constants.chainlink_BTC);
    }

    function test_GetDirectPrice() public view {
        uint256 price = chainlinkPrice.getInBase(AAVE, WETH);
        assertTrue(price > 2e16); // AAVE ~= 100 USD -> price in eth ~= 0.02
    }

    function test_GetDerivedPrice() public view {
        uint256 price = chainlinkPrice.getInBase(AAVE, DAI);
        assertTrue(price > 100e18); // AAVE ~= 100 USD -> price in DAI ~= 100
    }

    function test_GetWBTCPrice() public view {
        uint256 price = chainlinkPrice.getInBase(WBTC, USDC);
        assertTrue(price > 50e6); // WBTC ~= 50k USD -> price in USDC ~= 50k
    }

    function test_GetBTCUSDPrice() public view {
        uint256 price = chainlinkPrice.getInUSD(WBTC);
        assertTrue(price > 50e8); // WBTC ~= 50k USD -> price in USD ~= 50k
    }

    function test_GetWstETHPrice() public view {
        uint256 wstethPrice = chainlinkPrice.getInUSD(WSTETH);
        uint256 ethPrice = chainlinkPrice.getInUSD(WETH);
        assertTrue(wstethPrice > ethPrice);
    }

    function test_RevertStalePriceFeed() public {
        // Mock stale timestamp
        vm.mockCall(
            FEED_REGISTRY,
            abi.encodeWithSelector(FeedRegistryInterface.latestRoundData.selector),
            abi.encode(0, 1, 0, block.timestamp - 3 days, 0)
        );

        vm.expectRevert(IChainlinkPrice.CL_PRICE_STALE_PRICE_FEED.selector);
        chainlinkPrice.getInUSD(WBTC);
    }

    function test_RevertZeroPrice() public {
        // Mock zero price
        vm.mockCall(
            FEED_REGISTRY,
            abi.encodeWithSelector(FeedRegistryInterface.latestRoundData.selector),
            abi.encode(0, 0, 0, block.timestamp, 0)
        );

        vm.expectRevert(IChainlinkPrice.CL_PRICE_NON_POSITIVE_PRICE.selector);
        chainlinkPrice.getInUSD(WBTC);
    }

    function test_GetLinkingDenominationPrice() public view {
        uint256 price = chainlinkPrice.getInUSD(chainlinkPrice.LINKING_DENOMINATION());
        assertEq(price, 1e8); // 8 decimals for USD price
    }

    function test_RevertBasePriceUnavailable() public {
        // Mock revert for base price
        vm.mockCallRevert(
            FEED_REGISTRY,
            abi.encodeWithSelector(FeedRegistryInterface.latestRoundData.selector),
            "Feed not found"
        );

        vm.expectRevert("Feed not found");
        chainlinkPrice.getInBase(AAVE, DAI);
    }

    function test_RevertQuotePriceUnavailable() public {
        // Mock revert for quote price
        vm.mockCall(
            FEED_REGISTRY,
            abi.encodeWithSelector(FeedRegistryInterface.latestRoundData.selector, AAVE),
            abi.encode(0, 1e8, 0, block.timestamp, 0)
        );
        vm.mockCallRevert(
            FEED_REGISTRY,
            abi.encodeWithSelector(FeedRegistryInterface.latestRoundData.selector, DAI),
            "Feed not found"
        );

        vm.expectRevert("Feed not found");
        chainlinkPrice.getInBase(AAVE, DAI);
    }
}
