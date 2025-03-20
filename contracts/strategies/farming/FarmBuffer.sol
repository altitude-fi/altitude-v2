// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/strategy/farming/IFarmBuffer.sol";

/**
 * @title FarmBuffer Contract
 * @dev Buffer to optimize farm interactions
 * @author Altitude Labs
 **/

contract FarmBuffer is IFarmBuffer, Ownable {
    /** @notice Buffer size */
    uint256 public override size;

    /** @notice Buffer current capacity */
    uint256 public override capacity;

    /** @notice Underlying token tracked by the buffer */
    address public immutable override token;

    /// @notice Check if the address is 0x0
    /// @param addr Address to check
    modifier notZeroAddress(address addr) {
        if (addr == address(0)) {
            revert FM_ZERO_ADDRESS();
        }
        _;
    }

    /// @param asset The token the buffer is managing
    constructor(address asset) notZeroAddress(asset) {
        token = asset;
    }

    /// @notice Add underlying tokens to the buffer
    /// @param amount Number of tokens to be added
    /// @return overFillAmount Amount over the size
    function fill(uint256 amount) external onlyOwner returns (uint256 overFillAmount) {
        uint256 fullFillAmount = capacityMissing();
        if (amount > fullFillAmount) {
            overFillAmount = amount - fullFillAmount;
            amount = fullFillAmount;
        }

        capacity += amount;

        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
    }

    /// @notice Remove underlying tokens to the buffer and transfer them to the msg.sender
    /// @param amount Number of tokens to be removed
    /// @return amountWithdrawn Amount that left the buffer
    function empty(uint256 amount) external onlyOwner returns (uint256 amountWithdrawn) {
        if (amount > capacity) {
            amount = capacity;
        }

        capacity -= amount;
        amountWithdrawn = amount;

        TransferHelper.safeTransfer(token, msg.sender, amount);
    }

    /// @notice Returns the amount that has been taken out
    function capacityMissing() public view override returns (uint256) {
        return size - capacity;
    }

    /// @notice Increase the capacity & size of the buffer
    function increaseSize(uint256 increase) external override onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance - capacity < increase) {
            revert FM_WRONG_INCREASE();
        }

        size += increase;
        capacity += increase;
    }

    /// @notice Decrease the capacity & size of the buffer
    function decreaseSize(uint256 decrease, address to) external override onlyOwner notZeroAddress(to) {
        if (capacity < decrease) {
            revert FM_WRONG_DECREASE();
        }

        size -= decrease;
        capacity -= decrease;
        TransferHelper.safeTransfer(token, to, decrease);
    }

    /// @notice Decrease the entire capacity of the buffer
    function decreaseCapacity(address to) external override onlyOwner notZeroAddress(to) {
        uint256 decrease = capacity;
        size -= decrease;
        capacity -= decrease;
        TransferHelper.safeTransfer(token, to, decrease);
    }
}
