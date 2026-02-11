// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "./IBaseERC4626.sol";
import "../../../external/IMerklDistributor.sol";

/**
 * @author Altitude Protocol
 **/

interface IStrategy4626Merkl is IBaseERC4626 {
    event SetDistributor(address oldDistributor, address newDistributor);

    function merklDistributor() external returns (IMerklDistributor);

    function setDistributor(address merklDistributor_) external;

    function claimMerklRewards(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
