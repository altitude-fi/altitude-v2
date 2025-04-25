// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import "../../contracts/common/ProxyExtension.sol";

contract FooStorage {
    uint256 public bar = 1;
}

contract Foo is FooStorage {
    function setter(uint256 bar_) public {
        bar = bar_;
    }

    function returner(uint256 a, uint256 b) public pure returns (uint256[] memory) {
        uint256[] memory out = new uint256[](2);
        out[0] = a;
        out[1] = b;
        return out;
    }

    function reverter() public pure {
        revert("REASON");
    }
}

// Storage alignment!
contract ProxyExtensionTest is FooStorage, ProxyExtension, Test {
    Foo foo;

    function setUp() public {
        bar = 0;
        foo = new Foo();
    }

    function test_execReturn() public {
        uint256[] memory out = abi.decode(
            _exec(address(foo), abi.encodeWithSelector(Foo.returner.selector, uint256(1), uint256(2))),
            (uint256[])
        );

        assertEq(out.length, 2);
        assertEq(out[0], 1);
        assertEq(out[1], 2);
    }

    function test_execSet() public {
        assertEq(foo.bar(), 1, "Initial manager storage");
        assertEq(bar, 0, "Initial this storage");

        _exec(address(foo), abi.encodeWithSelector(Foo.setter.selector, uint256(3)));

        assertEq(foo.bar(), 1, "Doesn't write to manager storage");
        assertEq(bar, 3, "Writes to this storage");
    }

    function test_execRevert() public {
        vm.expectRevert("REASON");
        _exec(address(foo), abi.encodeWithSelector(Foo.reverter.selector));
    }
}
