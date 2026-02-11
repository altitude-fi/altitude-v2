// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/console.sol";

import "../FarmStrategyIntegrationTest.sol";
import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {Strategy4626Merkl, IStrategy4626Merkl, IMerklDistributor} from "../../../../../contracts/strategies/farming/strategies/erc4626/Strategy4626Merkl.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";

abstract contract GenericVault is FarmStrategyIntegrationTest {
    IStrategy4626Merkl private genericStrategy;

    function _setUp(address externalVault) internal {
        DEPOSIT = 1000e6;
        FEE_TOLERANCE = 1e13; // 0.001% fee acceptable

        IERC4626 vault4626 = IERC4626(externalVault);

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(vault4626.asset());
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = Constants.CRV;

        address[] memory nonSkimableAssets = new address[](3);
        nonSkimableAssets[0] = Constants.USDC;
        nonSkimableAssets[1] = vault4626.asset();
        nonSkimableAssets[2] = Constants.CRV;

        // address(this) is left as the owner of the strategy
        genericStrategy = new Strategy4626Merkl(
            dispatcher,
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            vault4626,
            rewardAssets,
            nonSkimableAssets,
            Constants.merkl_Distributor
        );

        farmStrategy = genericStrategy;
    }

    function _accumulateRewards() internal virtual override returns (address[] memory) {
        mintToken(Constants.CRV, address(farmStrategy), 100 * 10 ** IToken(Constants.CRV).decimals());

        address[] memory rewards = new address[](1);
        rewards[0] = Constants.CRV;
        return rewards;
    }

    function test_setDistributor() public {
        assertEq(Constants.merkl_Distributor, address(genericStrategy.merklDistributor()));

        vm.prank(makeAddr("someUser"));
        vm.expectRevert("Ownable: caller is not the owner");
        genericStrategy.setDistributor(makeAddr("distributor2"));

        genericStrategy.setDistributor(makeAddr("distributor2"));
        assertEq(makeAddr("distributor2"), address(genericStrategy.merklDistributor()));
    }

    function test_RewardsRecognition() public override {
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();
        uint256 balanceBefore = farmStrategy.balance();
        _accumulateRewards();

        address[] memory tokens;
        uint256[] memory amounts;
        bytes32[][] memory proofs;

        vm.mockCall(
            Constants.merkl_Distributor,
            abi.encodeWithSelector(IMerklDistributor.claim.selector),
            abi.encode()
        );

        genericStrategy.claimMerklRewards(tokens, amounts, proofs);
        uint256 rewards = genericStrategy.recogniseRewardsInBase();

        uint256 balanceAfter = farmStrategy.balance();
        assertTrue(balanceBefore == balanceAfter);
        assertTrue(asset.balanceOf(dispatcher) == rewards);
    }

    function test_RecogniseRewardsRecoversLoss() public {
        _mintAsset(dispatcher, DEPOSIT * 2);

        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        // create loss
        vm.deal(address(farmStrategy), 1 ether);
        vm.startPrank(address(farmStrategy));
        genericStrategy.vault().transfer(
            address(1),
            (genericStrategy.vault().balanceOf(address(farmStrategy)) * 2) / 100
        );
        vm.stopPrank();

        // deposit to trigger drop update
        vm.startPrank(dispatcher);
        asset.approve(address(farmStrategy), DEPOSIT);
        farmStrategy.deposit(DEPOSIT);
        vm.stopPrank();

        // we have a 2% drop
        assertApproxEqRel(Strategy4626Merkl(address(genericStrategy)).dropPercentage(), 0.02e18, 0.0005e18);

        // get rewards
        _accumulateRewards();
        address[] memory tokens;
        uint256[] memory amounts;
        bytes32[][] memory proofs;
        vm.mockCall(
            Constants.merkl_Distributor,
            abi.encodeWithSelector(IMerklDistributor.claim.selector),
            abi.encode()
        );

        // about 1000 usdc rewards
        genericStrategy.claimMerklRewards(tokens, amounts, proofs);
        uint256 rewards = genericStrategy.recogniseRewardsInBase();

        // drop cleared
        assertEq(Strategy4626Merkl(address(genericStrategy)).dropPercentage(), 0);

        // create loss
        vm.startPrank(address(farmStrategy));
        genericStrategy.vault().transfer(
            address(1),
            (genericStrategy.vault().balanceOf(address(farmStrategy)) * 2) / 100
        );
        vm.stopPrank();

        // we have a 2% drop again
        assertApproxEqRel(Strategy4626Merkl(address(genericStrategy)).currentDropPercentage(), 0.02e18, 0.0005e18);
    }
}
