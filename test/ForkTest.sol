pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

abstract contract ForkTest is Test {
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("FORK_URL"));
        vm.rollFork(20000000);
    }
}
