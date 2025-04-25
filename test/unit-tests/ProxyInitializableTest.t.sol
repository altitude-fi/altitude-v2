// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ProxyInitializable} from "../../contracts/common/ProxyInitializable.sol";

contract ImplementationContract {
    uint256 public version;

    function setVersion(uint256 version_) public {
        version = version_;
    }

    function foo() public pure virtual returns (uint256) {
        return 1;
    }
}

contract ImplementationContractV2 is ImplementationContract {
    function foo() public pure override returns (uint256) {
        return 2;
    }
}

contract ProxyInitializableTest is Test {
    ProxyInitializable proxy;
    ImplementationContract impl = new ImplementationContract();
    ImplementationContract proxiedImpl;

    address someUser = makeAddr("someUser");
    address adminUser = makeAddr("adminUser");

    function setUp() public {
        proxy = new ProxyInitializable{salt: "123"}();
        proxy.initialize(
            adminUser,
            address(impl),
            abi.encodeWithSelector(ImplementationContract.setVersion.selector, uint256(1))
        );
        proxiedImpl = ImplementationContract(address(proxy));
    }

    function test_correctInitialization() public view {
        assertEq(address(proxiedImpl), address(proxy));
        assertEq(proxiedImpl.version(), 1);
        assertEq(proxiedImpl.foo(), 1);
    }

    function test_secondInitialization() public {
        vm.expectRevert("ALREADY_INITIALIZED");
        proxy.initialize(
            someUser,
            address(impl),
            abi.encodeWithSelector(ImplementationContract.setVersion.selector, uint256(2))
        );
    }

    function test_changeAdmin() public {
        vm.prank(someUser);
        vm.expectRevert("NOT_PROXY_ADMIN");
        proxy.changeAdmin(someUser);

        vm.prank(adminUser);
        proxy.changeAdmin(someUser);

        vm.prank(adminUser);
        vm.expectRevert("NOT_PROXY_ADMIN");
        proxy.changeAdmin(someUser);

        vm.prank(someUser);
        proxy.changeAdmin(adminUser);

        vm.prank(someUser);
        vm.expectRevert("NOT_PROXY_ADMIN");
        proxy.changeAdmin(someUser);

        vm.prank(adminUser);
        proxy.changeAdmin(adminUser);
    }

    function test_upgradeTo() public {
        address newImpl = address(new ImplementationContractV2());

        vm.prank(someUser);
        vm.expectRevert("NOT_PROXY_ADMIN");
        proxy.upgradeTo(newImpl);

        vm.prank(adminUser);
        vm.expectRevert("ZERO_IMPLEMENTATION_NOT_ALLOWED");
        proxy.upgradeTo(address(0));

        assertEq(proxiedImpl.foo(), 1);
        assertEq(proxiedImpl.version(), 1);
        vm.prank(adminUser);
        proxy.upgradeTo(newImpl);
        assertEq(proxiedImpl.foo(), 2);
        assertEq(proxiedImpl.version(), 1);

        vm.prank(adminUser);
        proxy.upgradeTo(address(impl));
        assertEq(proxiedImpl.foo(), 1);
        assertEq(proxiedImpl.version(), 1);
    }
}
