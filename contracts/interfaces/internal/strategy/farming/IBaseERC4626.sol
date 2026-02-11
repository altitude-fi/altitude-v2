// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./IFarmStrategy.sol";

/**
 * @author Altitude Protocol
 **/

interface IBaseERC4626 is IFarmStrategy {
    function vault() external returns (IERC4626);
}
