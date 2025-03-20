// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import {TokensGenerator} from "../utils/TokensGenerator.sol";
import {BaseGetter} from "../base/BaseGetter.sol";
import "./../../contracts/strategies/farming/strategies/convex/StrategyGenericPool.sol";
import "./../../contracts/interfaces/internal/strategy/farming/IConvexFarmStrategy.sol";

contract ExtraReward {
    address public rewardToken;

    constructor() {
        rewardToken = BaseGetter.getBaseERC20(18);
    }
}

contract CRVRewardsMock is TokensGenerator {
    address public asset;
    address public convex;
    address public extraReward;
    address[] public rewards;
    bool public toReceiveRewards;

    constructor(address curveLPToken, address[] memory rewardTokens) {
        toReceiveRewards = true;
        asset = curveLPToken;
        extraReward = address(new ExtraReward());

        rewards.push(ExtraReward(extraReward).rewardToken());
        for (uint256 i; i < rewardTokens.length; i++) {
            rewards.push(rewardTokens[i]);
        }
    }

    function setConvex(address convexMock) external {
        convex = convexMock;
    }

    function deactivateRewards() external {
        toReceiveRewards = false;
    }

    function balanceOf(address) external view returns (uint256) {
        return IToken(asset).balanceOf(address(this));
    }

    function decimals() external view returns (uint256) {
        return IToken(asset).decimals();
    }

    function withdraw(uint256 amount, bool) external {
        IToken(asset).transfer(convex, amount);
    }

    function withdrawAll(bool) external {
        IToken(asset).transfer(convex, IToken(asset).balanceOf(address(this)));
    }

    function getReward(address recipient, bool sendExtra) external returns (bool) {
        if (toReceiveRewards) {
            for (uint256 i = 1; i < rewards.length; i++) {
                mintToken(rewards[i], recipient, 10**IToken(rewards[i]).decimals());
            }

            if (sendExtra) {
                mintToken(rewards[0], recipient, 10**IToken(rewards[0]).decimals());
            }
        }

        return true;
    }

    function getRewardRate(uint256 i) external view returns (uint256) {
        return 10**IToken(rewards[i]).decimals();
    }

    function extraRewardsLength() external pure returns (uint256) {
        return 1;
    }

    function extraRewards(uint256) external view returns (address) {
        return extraReward;
    }
}
