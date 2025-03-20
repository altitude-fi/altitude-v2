// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title TestVault
 * @dev Contarct for testing the interest accrual in the lender providers (test ONLY purpose)
 * @author Altitude Labs
 **/

import "../vaults/v1/VaultCore.sol";
import "../interfaces/external/strategy/lending/Aave/IWETH.sol";

contract TestVault is VaultCoreV1 {
    function mintSupplyToken(address to, uint256 amount) external {
        supplyToken.mint(to, amount);
    }

    function mintDebtToken(address to, uint256 amount) external {
        debtToken.mint(to, amount);
    }

    function _preDeposit(uint256 amount) internal override {}

    function _postWithdraw(
        uint256, /* withdrawAmount */
        address /* to */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function vaultCoreDeposit(uint256 amount) public payable {
        IWETH(supplyUnderlying).deposit{value: msg.value}();
        _deposit(amount, msg.sender);
    }

    function depositERC20(uint256 amount, address onBehalfOf) public payable {
        TransferHelper.safeTransferFrom(supplyUnderlying, onBehalfOf, address(this), amount);
        TransferHelper.safeTransfer(supplyUnderlying, activeLenderStrategy, amount);

        ILenderStrategy(activeLenderStrategy).deposit(amount);
    }

    receive() external payable {}
}
