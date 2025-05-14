// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/strategies/farming/strategies/FarmDropStrategy.sol";

contract BaseFarmStrategy is FarmDropStrategy {
    uint256 public farmAssetAmount;

    constructor(
        address assetAddress,
        address dispatcherAddress,
        address rewardsAddress,
        address[] memory rewardAssets_,
        address swapAddress
    ) FarmDropStrategy(assetAddress, dispatcherAddress, rewardsAddress, rewardAssets_, swapAddress) {}

    function setFarmAssetAmount(uint256 amount) external {
        farmAssetAmount = amount;
    }

    function _deposit(uint256) internal override {}

    function _withdraw(uint256) internal override {}

    function _emergencyWithdraw() internal override {}

    function _emergencySwap(address[] calldata) internal override {}

    function _getFarmAssetAmount() internal view virtual override returns (uint256) {
        return farmAssetAmount;
    }

    function _recogniseRewardsInBase() internal override {
        super._recogniseRewardsInBase();
    }

    function _swap(address, address, uint256 amount) internal pure override returns (uint256) {
        return amount;
    }
}
