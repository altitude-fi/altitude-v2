// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IToken} from "../interfaces/IToken.sol";
import "../../contracts/interfaces/internal/oracles/IPriceSource.sol";

// [DEFAULT] Returns price 1:1 ratio for every token
contract BasePriceSource is IPriceSource {
    mapping(address => mapping(address => uint256)) public prices;

    function setInBase(address from, address to, uint256 price) public {
        prices[from][to] = price;
    }

    function getInBase(address from, address to) external view returns (uint256) {
        if (prices[from][to] == 0) {
            return 10 ** IToken(to).decimals();
        }

        return prices[from][to];
    }

    function getInUSD(address) external pure returns (uint256) {
        return 1e6;
    }
}
