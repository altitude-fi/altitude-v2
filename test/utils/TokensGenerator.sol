// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import {Constants} from "../../scripts/deployer/Constants.sol";

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";

abstract contract TokensGenerator is Test {
    using stdStorage for StdStorage;

    function mintToken(address token, address to, uint256 amount) public {
        stdstore.target(token).sig("balanceOf(address)").with_key(to).depth(0).checked_write(
            IToken(token).balanceOf(to) + amount
        );

        stdstore.target(token).sig("totalSupply()").checked_write(IToken(token).totalSupply() + amount);
    }

    function burnToken(address token, address to, uint256 amount) public {
        stdstore.target(token).sig("balanceOf(address)").with_key(to).depth(0).checked_write(
            IToken(token).balanceOf(to) - amount
        );

        stdstore.target(token).sig("totalSupply()").checked_write(IToken(token).totalSupply() - amount);
    }

    function transferToken(address token, address from, address to, uint256 amount) public {
        stdstore.target(token).sig("balanceOf(address)").with_key(from).depth(0).checked_write(
            IToken(token).balanceOf(from) - amount
        );
        stdstore.target(token).sig("balanceOf(address)").with_key(to).depth(0).checked_write(
            IToken(token).balanceOf(to) + amount
        );
    }
}
