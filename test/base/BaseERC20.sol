// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BaseERC20 is ERC20 {
    uint8 private _decimals;

    constructor(uint8 _decimalsNumber, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _decimals = _decimalsNumber;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function burn(address to, uint256 amount) external {
        _burn(to, amount);
    }
}
