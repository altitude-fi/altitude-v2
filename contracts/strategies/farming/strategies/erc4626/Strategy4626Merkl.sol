// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./BaseERC4626.sol";
import "../../../../libraries/uniswap-v3/TransferHelper.sol";
import {IStrategy4626Merkl, IMerklDistributor} from "../../../../interfaces/internal/strategy/farming/IStrategy4626Merkl.sol";

/**
 * @title Strategy4626Merkl Contract
 * @dev Contract for interacting with ERC4626 vaults with Merkl rewards
 * @author Altitude Labs
 **/

contract Strategy4626Merkl is BaseERC4626, IStrategy4626Merkl {
    IMerklDistributor public merklDistributor;

    constructor(
        address farmDispatcherAddress_,
        address rewardsAddress_,
        address swapStrategy_,
        IERC4626 vault_,
        address[] memory rewardAssets_,
        address[] memory nonSkimAssets_,
        address merklDistributor_
    ) BaseERC4626(farmDispatcherAddress_, rewardsAddress_, swapStrategy_, vault_, rewardAssets_, nonSkimAssets_) {
        merklDistributor = IMerklDistributor(merklDistributor_);
    }

    /// @notice Set rewards distributor address
    /// @param merklDistributor_ Rewards distributor address
    function setDistributor(address merklDistributor_) external override onlyOwner {
        emit SetDistributor(address(merklDistributor), merklDistributor_);
        merklDistributor = IMerklDistributor(merklDistributor_);
    }

    /// @notice Claim rewards from Merkl
    /// @param tokens ERC20 token claimed
    /// @param amounts Amount of tokens to claim
    /// @param proofs Array of hash proofs for each token
    function claimMerklRewards(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) public override {
        address[] memory users = new address[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            users[i] = address(this);
        }
        merklDistributor.claim(users, tokens, amounts, proofs);
    }
}
