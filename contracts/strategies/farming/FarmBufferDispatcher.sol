// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./FarmBuffer.sol";
import "./FarmDispatcher.sol";
import "../../interfaces/internal/strategy/farming/IFarmBufferDispatcher.sol";

/**
 * @title FarmBufferDispatcher Contract
 * @dev Buffer to optimize farm interactions
 * @author Altitude Labs
 **/

contract FarmBufferDispatcher is FarmDispatcher, IFarmBufferDispatcher {
    /** @notice Buffer for gas optimizaiton */
    IFarmBuffer public override farmBuffer;

    function initialize(
        address vaultAddress,
        address workingAsset,
        address owner
    ) public override(FarmDispatcher, IFarmDispatcher) initializer {
        super._initialize(vaultAddress, workingAsset, owner);

        farmBuffer = new FarmBuffer(workingAsset);
    }

    /// @notice Fill the buffer first
    function _dispatch(uint256 amount) internal override {
        uint256 overFillAmount = _fillBuffer(amount);
        super._dispatch(overFillAmount);
    }

    /// @notice Empty the buffer first
    function _withdraw(uint256 amountRequested) internal override returns (uint256 amountWithdrawn) {
        uint256 bufferCapacity = farmBuffer.capacity();

        if (amountRequested > bufferCapacity || bufferCapacity >= balance()) {
            amountWithdrawn = super._withdraw(amountRequested + farmBuffer.capacityMissing());

            amountWithdrawn = _fillBuffer(amountWithdrawn);
        } else {
            amountWithdrawn = farmBuffer.empty(amountRequested);
        }
    }

    /// @notice Return the balance that can be withdrawn at the moment
    /// @return totalBalance in asset
    function balance() public view override(FarmDispatcher, IFarmDispatcher) returns (uint256 totalBalance) {
        totalBalance = super.balance();
        uint256 bufferToRefill = farmBuffer.capacityMissing();

        if (bufferToRefill > totalBalance) {
            totalBalance = 0;
        } else {
            totalBalance -= bufferToRefill;
        }
    }

    /// @notice Increase buffer size
    /// @param increase Number of tokens to be added
    function increaseBufferSize(uint256 increase) external override onlyRole(Roles.BETA) {
        TransferHelper.safeTransferFrom(asset, msg.sender, address(farmBuffer), increase);
        farmBuffer.increaseSize(increase);

        emit BufferSizeIncreased(increase);
    }

    /// @notice Decrease buffer size
    /// @param decrease Number of tokens to be removed
    function decreaseBufferSize(uint256 decrease) external override onlyRole(Roles.BETA) {
        farmBuffer.decreaseSize(decrease, msg.sender);

        emit BufferSizeDecreased(decrease);
    }

    /// @notice Decrease as much as possible capacity
    /// @dev The purpose of the function is when the last users exists the protocol
    /// @dev there is a risk for the buffer to become locked in the farm provider
    /// @dev The admins should be able to withdraw the buffer from the farm provider
    function decreaseBufferCapacity() public virtual override onlyRole(Roles.BETA) {
        uint256 amountWithdrawn = super._withdraw(farmBuffer.capacityMissing());
        _fillBuffer(amountWithdrawn);

        uint256 capacity = farmBuffer.capacity();
        farmBuffer.decreaseCapacity(msg.sender);

        emit BufferCapacityDecreased(capacity);
    }

    /// @notice Uses the balance to refill the buffer
    /// @param amount Amount to be used for refilling the buffer
    /// @return amountLeft What is left after refilling the buffer
    function _fillBuffer(uint256 amount) internal returns (uint256 amountLeft) {
        amountLeft = amount;
        if (amountLeft > 0) {
            TransferHelper.safeApprove(asset, address(farmBuffer), amountLeft);
            amountLeft = farmBuffer.fill(amountLeft);
        }
    }
}
