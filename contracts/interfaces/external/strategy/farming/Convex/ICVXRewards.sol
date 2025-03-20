// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICVXRewards {
    event RewardPaid(address indexed user, uint256 reward);

    function earned(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function rewardToken() external view returns (address);

    function getReward() external;

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount, bool claim) external;

    function withdrawAll(bool claim) external;

    function extraRewards(uint256) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    function userRewardPerTokenPaid(address account) external view returns (uint256);
}
