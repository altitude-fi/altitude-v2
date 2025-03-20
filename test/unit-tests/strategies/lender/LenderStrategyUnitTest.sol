pragma solidity 0.8.28;

import {ForkTest} from "../../../ForkTest.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TokensGenerator} from "../../../utils/TokensGenerator.sol";

abstract contract LenderStrategyUnitTest is ForkTest, TokensGenerator {
    address public vault;
    IERC20Metadata public supplyAsset;
    IERC20Metadata public borrowAsset;
    uint256 public constant MAX_DEPOSIT_FEE = 100;

    uint256 public DEPOSIT = 1000e18;
    uint256 public BORROW = 100e18;

    function setUp() public override {
        super.setUp();
        _setUp();
    }

    function _setUp() internal virtual;
}
