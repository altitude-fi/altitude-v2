// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../FarmStrategyIntegrationTest.sol";
import {IToken} from "../../../../interfaces/IToken.sol";
import {Constants} from "../../../../../scripts/deployer/Constants.sol";
import {MorphoVault} from "../../../../../contracts/strategies/farming/strategies/morpho/MorphoVault.sol";
import {FarmDispatcher} from "../../../../../contracts/strategies/farming/FarmDispatcher.sol";
import {BaseGetter} from "../../../../base/BaseGetter.sol";

contract MorphoStrategy is FarmStrategyIntegrationTest {
    IERC4626 public morphoVault;

    function _setUp() internal override {
        DEPOSIT = 1000e6;
        FEE_TOLERANCE = 1e13; // 0.001% fee acceptable

        morphoVault = IERC4626(Constants.morpho_Vault_DAI);

        asset = IERC20Metadata(Constants.USDC);
        farmAsset = IERC20Metadata(morphoVault.asset());
        dispatcher = address(new FarmDispatcher());
        FarmDispatcher(dispatcher).initialize(address(this), Constants.USDC, address(this));

        address[] memory rewardAssets = new address[](1);
        rewardAssets[0] = Constants.CRV;

        address[] memory nonSkimableAssets = new address[](3);
        nonSkimableAssets[0] = Constants.USDC;
        nonSkimableAssets[1] = morphoVault.asset();
        nonSkimableAssets[2] = Constants.CRV;

        farmStrategy = new MorphoVault(
            dispatcher,
            dispatcher,
            BaseGetter.getBaseSwapStrategy(BaseGetter.getBasePriceSource()),
            morphoVault,
            rewardAssets,
            nonSkimableAssets
        );
    }

    function _accumulateRewards() internal virtual override returns (address[] memory) {
        mintToken(Constants.CRV, address(farmStrategy), 100 * 10 ** IToken(Constants.CRV).decimals());

        address[] memory rewards = new address[](1);
        rewards[0] = Constants.CRV;
        return rewards;
    }
}
