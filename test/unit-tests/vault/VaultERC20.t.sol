pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

import {BaseGetter} from "../../base/BaseGetter.sol";
import {IToken} from "../../interfaces/IToken.sol";

import {VaultERC20} from "../../../contracts/vaults/v1/ERC20/VaultERC20.sol";
import {IVaultStorage} from "../../../contracts/interfaces/internal/vault/IVaultStorage.sol";

contract VaultERC20Mock is VaultERC20 {
    // For the purpose of testing, we are making that function public
    function preDeposit(uint256 amount) external {
        super._preDeposit(amount);
    }

    // For the purpose of testing, we are making that function public
    function postWithdraw(uint256 amount, address to) external returns (uint256) {
        return super._postWithdraw(amount, to);
    }
}

contract VaultERC20Test is Test {
    using stdStorage for StdStorage;

    IToken public token;
    VaultERC20Mock public vault;

    function setUp() public {
        token = IToken(BaseGetter.getBaseERC20(18));
        vault = new VaultERC20Mock();

        stdstore.target(address(vault)).sig("supplyUnderlying()").checked_write(address(token));
    }

    function test_PreDeposit() public {
        token.mint(address(this), 10e18);
        token.approve(address(vault), 10e18);

        vault.preDeposit(10e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(vault)), 10e18);
    }

    function test_PostWithdraw() public {
        token.mint(address(this), 10e18);
        token.approve(address(vault), 10e18);

        vault.preDeposit(10e18);
        vault.postWithdraw(10e18, address(this));

        assertEq(token.balanceOf(address(this)), 10e18);
        assertEq(token.balanceOf(address(vault)), 0);
    }
}
