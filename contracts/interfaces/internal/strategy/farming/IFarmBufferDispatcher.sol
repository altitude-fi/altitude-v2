// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

import "./IFarmBuffer.sol";
import "./IFarmDispatcher.sol";

interface IFarmBufferDispatcher is IFarmDispatcher {
    event BufferActivated(address farmBuffer, address borrowAsset, uint256 bufferSize);
    event BufferSizeIncreased(uint256 increase);
    event BufferSizeDecreased(uint256 decrease);
    event BufferCapacityDecreased(uint256 capacity);

    function farmBuffer() external view returns (IFarmBuffer);

    function increaseBufferSize(uint256 increase) external;

    function decreaseBufferSize(uint256 decrease) external;

    function decreaseBufferCapacity() external;
}
