// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

/**
 * @author Altitude Protocol
 **/

interface IFarmBuffer {
    error FM_ZERO_ADDRESS();
    error FM_WRONG_INCREASE();
    error FM_WRONG_DECREASE();

    function size() external view returns (uint256);

    function capacity() external view returns (uint256);

    function token() external view returns (address);

    function fill(uint256 amount) external returns (uint256 overFillAmount);

    function empty(uint256 amount) external returns (uint256 amountWithdrawn);

    function capacityMissing() external view returns (uint256);

    function increaseSize(uint256 increase) external;

    function decreaseSize(uint256 decrease, address to) external;

    function decreaseCapacity(address to) external;
}
