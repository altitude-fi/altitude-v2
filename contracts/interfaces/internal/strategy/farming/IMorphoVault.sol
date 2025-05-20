// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./IFarmStrategy.sol";

/**
 * @author Altitude Protocol
 **/

interface IMorphoVault is IFarmStrategy {
    function morphoVault() external returns (IERC4626);
}
