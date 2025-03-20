// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./IFarmStrategy.sol";

/**
 * @author Altitude Protocol
 **/
interface IFarmDropStrategy is IFarmStrategy {
    event ResetDropPercentage();

    error FDS_DROP_EXCEEDED(uint256 current, uint256 threshold);
    error FDS_OUT_OF_BOUNDS();

    function dropThreshold() external view returns (uint256);

    function dropPercentage() external view returns (uint256);

    function expectedBalance() external view returns (uint256);

    function currentDropPercentage() external view returns (uint256);

    function DROP_UNITS() external view returns (uint256);

    function reset() external;
}
