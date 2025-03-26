pragma solidity 0.8.28;

import "../FarmStrategyIntegrationTest.sol";
import {IToken} from "../../../../interfaces/IToken.sol";

abstract contract ConvexStrategy is FarmStrategyIntegrationTest {
    function _accumulateRewards() internal virtual override returns (address[] memory) {
        mintToken(Constants.CRV, address(farmStrategy), 100 * 10 ** IToken(Constants.CRV).decimals());
        mintToken(Constants.CVX, address(farmStrategy), 100 * 10 ** IToken(Constants.CVX).decimals());

        address[] memory rewards = new address[](2);
        rewards[0] = Constants.CRV;
        rewards[1] = Constants.CVX;
        return rewards;
    }
}
