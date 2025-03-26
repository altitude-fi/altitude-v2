// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IConvex {
    event Deposited(address indexed user, uint256 indexed poolid, uint256 amount);

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);

    function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

    function lockRewards() external view returns (address);

    function stakerRewards() external view returns (address);

    function lockFees() external view returns (address);

    function earmarkRewards(uint256 _pid) external returns (bool);

    function staker() external view returns (address);

    function claimRewards(uint256 _pid, address _gauge) external returns (bool);

    function crv() external view returns (address);
}
