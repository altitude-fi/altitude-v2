pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {BaseETH} from "../../base/BaseETH.sol";

import {VaultETH} from "../../../contracts/vaults/v1/ETH/VaultETH.sol";
import {IVaultCoreV1} from "../../../contracts/interfaces/internal/vault/IVaultCore.sol";

contract VaultETHMock is VaultETH {
    // For the purpose of testing, we are making that function public
    function preDeposit(uint256 amount) external payable {
        super._preDeposit(amount);
    }

    // For the purpose of testing, we are making that function public
    function postWithdraw(uint256 amount, address to) external returns (uint256) {
        return super._postWithdraw(amount, to);
    }
}

contract VaultETHTest is Test {
    using stdStorage for StdStorage;

    BaseETH public token;
    VaultETHMock public vault;

    function setUp() public {
        token = new BaseETH();
        vault = new VaultETHMock();

        vm.deal(address(this), 1 ether);

        stdstore.target(address(vault)).sig("supplyUnderlying()").checked_write(address(token));
    }

    function test_ReceiveRevertsIfNotSupplyUnderlying() public {
        (bool success, ) = address(vault).call{value: 1 ether}(new bytes(0));
        assertEq(success, false);
    }

    function test_PreDeposit() public {
        vault.preDeposit{value: 1 ether}(1 ether);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(vault)), 1 ether);
    }

    function test_PreDepositInsufficientAmount() public {
        vm.expectRevert(IVaultCoreV1.VC_V1_ETH_INSUFFICIENT_AMOUNT.selector);
        vault.preDeposit{value: 1 ether}(2 ether);
    }

    function test_PostWithdraw() public {
        address user = makeAddr("user");
        vault.preDeposit{value: 1 ether}(1 ether);
        vault.postWithdraw(1 ether, user);

        assertEq(address(user).balance, 1 ether);
        assertEq(token.balanceOf(address(vault)), 0);
    }
}
