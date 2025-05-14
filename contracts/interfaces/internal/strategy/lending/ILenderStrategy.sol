// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "../swap/ISwapStrategyConfiguration.sol";

/**
 * @author Altitude Protocol
 **/

interface ILenderStrategy is ISwapStrategyConfiguration {
    event SetMaxDepositFee(uint256 depositFee);
    event RewardsRecognition(uint256 rewards);

    error LS_ONLY_VAULT();
    error LS_ZERO_ADDRESS();
    error LS_DEPOSIT_FEE_TOO_BIG();
    error LS_WITHDRAW_INSUFFICIENT();
        error LS_BORROW_INSUFFICIENT(uint256 requestedBorrow, uint256 actualBorrow);
    error LS_INVALID_ASSET_PAIR();

    function vault() external view returns (address);

    function supplyAsset() external view returns (address);

    function borrowAsset() external view returns (address);

    function maxDepositFee() external view returns (uint256);

    function supplyPrincipal() external view returns (uint256);

    function borrowPrincipal() external view returns (uint256);

    function rewardsRecipient() external view returns (address);

    function setMaxDepositFee(uint256 depositFee) external;

    function deposit(uint256 amount) external returns (uint256);

    function withdraw(uint256 amount) external returns (uint256 amountOut);

    function borrow(uint256 amount) external;

    function repay(uint256 amount) external;

    function withdrawAll() external;

    function getLendingPool() external view returns (address);

    function borrowBalance() external view returns (uint256);

    function supplyBalance() external view returns (uint256);

    function hasSupplyLoss() external view returns (bool);

    function availableBorrowLiquidity() external view returns (uint256);

    function preSupplyLossSnapshot() external returns (uint256 supplyLoss, uint256 borrowLoss, uint256 fee);

    function updatePrincipal() external;

    function updatePrincipal(uint256 supplyPrincipal, uint256 borrowPrincipal) external;

    function getInBase(address fromAsset, address toAsset) external view returns (uint256);

    function convertToBase(uint256 amount, address fromAsset, address toAsset) external view returns (uint256);

    function paidLiquidationFee(uint256 supplyLoss) external view returns (uint256 fee);

    function recogniseRewardsInBase() external returns (uint256 rewards);
}
