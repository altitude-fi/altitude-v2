// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";

contract ConvexMock {
    address public asset;
    address public crvRewards;

    constructor(address curveLPToken, address crvRewardsMock) {
        asset = curveLPToken;
        crvRewards = crvRewardsMock;
    }

    function depositAll(uint256, bool) external returns (bool) {
        IToken(asset).transferFrom(msg.sender, crvRewards, IToken(asset).balanceOf(msg.sender));
        return true;
    }

    function withdraw(uint256, uint256 amount) external returns (bool) {
        IToken(asset).transfer(msg.sender, amount);
        return true;
    }

    function withdrawAll(uint256) external returns (bool) {
        IToken(asset).transfer(msg.sender, IToken(asset).balanceOf(address(this)));
        return true;
    }
}
