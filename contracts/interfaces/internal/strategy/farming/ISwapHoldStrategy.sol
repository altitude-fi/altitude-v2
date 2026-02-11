// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IFarmStrategy.sol";

/**
 * @author Altitude Protocol
 **/

interface ISwapHoldStrategy is IFarmStrategy {
    error SWAP_HOLD_SAME_ASSETS();
}
