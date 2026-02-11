// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";

contract MorphoVaultV2Mock {
    address public asset;

    constructor(address farmAsset) {
        asset = farmAsset;
    }

    function deposit(uint256 amount, address) external returns (uint256) {
        IToken(asset).transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function maxWithdraw(address) external view returns (uint256) {
        return 0;
    }

    function withdraw(uint256 assets, address receiver, address) external returns (uint256 shares) {
        IToken(asset).transfer(receiver, assets);
        return assets;
    }

    function maxRedeem(address) external view returns (uint256) {
        return 0;
    }

    function redeem(uint256 shares, address receiver, address) external returns (uint256) {
        IToken(asset).transfer(receiver, shares);
        return shares;
    }

    function balanceOf(address) external view returns (uint256) {
        return IToken(asset).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }
}
