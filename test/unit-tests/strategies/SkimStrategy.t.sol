// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IToken} from "../../interfaces/IToken.sol";
import {BaseGetter} from "../../base/BaseGetter.sol";
import {SkimStrategy} from "../../../contracts/strategies/SkimStrategy.sol";
import {ISkimStrategy} from "../../../contracts/interfaces/internal/strategy/ISkimStrategy.sol";

contract SkimStrategyTest is Test {
    address public nonSkimAsset;
    SkimStrategy public skimStrategy;

    function setUp() public {
        nonSkimAsset = BaseGetter.getBaseERC20(18);

        address[] memory nonSkimAssets = new address[](1);
        nonSkimAssets[0] = nonSkimAsset;
        skimStrategy = new SkimStrategy(nonSkimAssets);
    }

    function test_CorrectInitialization() public view {
        assertEq(skimStrategy.nonSkimAssets(nonSkimAsset), true);
    }

    function test_Skim() public {
        address receiver = makeAddr("receiver");
        address token = BaseGetter.getBaseERC20(18);
        IToken(token).mint(address(skimStrategy), 1e18);
        address[] memory assets = new address[](1);
        assets[0] = token;
        skimStrategy.skim(assets, receiver);
        assertEq(IToken(token).balanceOf(receiver), 1e18);
        assertEq(IToken(token).balanceOf(address(skimStrategy)), 0);
    }

    function test_SkimNonSkimAsset() public {
        address[] memory nonSkimAssets = new address[](2);
        nonSkimAssets[0] = nonSkimAsset;
        nonSkimAssets[1] = BaseGetter.getBaseERC20(18);

        vm.expectRevert(ISkimStrategy.SK_NON_SKIM_ASSET.selector);
        skimStrategy.skim(nonSkimAssets, address(skimStrategy));
    }

    function test_SkimUnauthorized() public {
        address receiver = makeAddr("receiver");
        address[] memory nonSkimAssets = new address[](0);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert("Ownable: caller is not the owner");
        skimStrategy.skim(nonSkimAssets, receiver);
    }
}
