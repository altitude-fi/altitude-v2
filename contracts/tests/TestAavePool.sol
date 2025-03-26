// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestAavePool {
    uint256 public mockATokenBalance;
    uint256 public constant FEE_PRECISION = 1e6;
    uint256 public feePercentage = 5e5;

    TestToken public mockBorrowToken;

    constructor() {
        mockBorrowToken = new TestToken();
    }

    function withdraw(address supplyAsset, uint256 amount, address to) public returns (uint256) {
        uint256 feeAmount = (amount * feePercentage) / FEE_PRECISION;
        uint256 amountAfterFee = amount - feeAmount;
        IERC20(supplyAsset).transfer(to, amountAfterFee);
        mockATokenBalance -= amountAfterFee;
        return amountAfterFee;
    }

    function deposit(address supplyAsset, uint256 amount, address, uint16) public {
        IERC20(supplyAsset).transferFrom(msg.sender, address(this), amount);
        mockATokenBalance += amount;
    }

    function getReserveTokensAddresses(address) public view returns (address, address, address) {
        return (address(this), address(0), address(mockBorrowToken));
    }

    function balanceOf(address) public view returns (uint256) {
        return mockATokenBalance;
    }

    function setBalance(uint256 _mockATokenBalance) public {
        mockATokenBalance = _mockATokenBalance;
    }

    function setBorrowBalance(uint256 _mockBorrowTokenBalance) public {
        mockBorrowToken.setBalance(_mockBorrowTokenBalance);
    }

    function setFee(uint256 _feePercentage) public {
        require(_feePercentage <= FEE_PRECISION, "Fee percentage exceeds precision");
        feePercentage = _feePercentage;
    }
}

contract TestToken {
    uint256 public mockBalance;

    function balanceOf(address) public view returns (uint256) {
        return mockBalance;
    }

    function setBalance(uint256 _mockBalance) public {
        mockBalance = _mockBalance;
    }
}
