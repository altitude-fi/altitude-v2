// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/uniswap-v3/TransferHelper.sol";
import "../interfaces/internal/strategy/ISkimStrategy.sol";

/**
 * @title SkimStrategy
 * @dev Contract for skiming assets
 * @author Altitude Labs
 **/

contract SkimStrategy is Ownable, ISkimStrategy {
    /** @notice Assets that are not allowed for skim */
    mapping(address => bool) public nonSkimAssets;

    /// @param assets Assets that are not allowed for skim
    constructor(address[] memory assets) {
        uint256 assetsLength = assets.length;
        for (uint256 i; i < assetsLength; ) {
            nonSkimAssets[assets[i]] = true;
            unchecked {
                ++i;
            }
        }
    }

    /** @notice Transfer tokens out of the strategy
     * @dev Used to even out distributions when rewards accrue in batches
     * @param assets Token addresses
     * @param receiver Receiving account
     */
    function skim(address[] calldata assets, address receiver) public override onlyOwner {
        if (receiver == address(0)) {
            revert SK_INVALID_RECEIVER();
        }

        uint256 assetsLength = assets.length;
        for (uint256 i; i < assetsLength; ) {
            if (nonSkimAssets[assets[i]]) {
                revert SK_NON_SKIM_ASSET();
            }

            TransferHelper.safeTransfer(assets[i], receiver, IERC20(assets[i]).balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }
}
