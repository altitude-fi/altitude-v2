// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IFarmDispatcher is IAccessControl {
    struct Strategy {
        bool active;
        uint256 maxAmount;
        uint256 totalDeposit;
        address prev;
        address next;
    }

    event Disable(uint256 amount);
    event Enable(uint256 amount);
    event Withdraw(uint256 amount);
    event WithdrawAll(uint256 amount);
    event SetStrategyMax(address strategyAddress, uint256 max);
    event SetStrategyPiority(address strategy, address strategyPosition);
    event Dispatch(uint256 amount);
    event StrategyError(address strategy, bytes lowLevelData);

    event DeactivateStrategy(address strategyAddress);
    event EmergencyDeactivateStrategy(address strategyAddress, uint256 amountWithdrawn);
    event AddStrategy(address strategyAddress, uint256 max, address position);
    event RecogniseRewards(uint256 allRewards, uint256 failedStrategies);

    error FD_ONLY_VAULT();
    error FD_VAULT_OR_OWNER();
    error FD_STRATEGY_EXISTS();
    error FS_EMPTY_STRATEGIES();
    error FS_STRATEGIES_MISMATCH();
    error FD_ZERO_STRATEGY_REMOVAL();
    error FD_STRATEGY_PRIORITY_THE_SAME();
    error FD_INACTIVE_STRATEGY();
    error FD_INACTIVE_STRATEGY_POSITION();

    function vault() external view returns (address);

    function asset() external view returns (address);

    function STRATEGY_ZERO() external view returns (address);

    function strategies(address)
        external
        view
        returns (
            bool,
            uint256,
            uint256,
            address,
            address
        );

    function initialize(
        address vaultAddress,
        address workingAsset,
        address owner
    ) external;

    function setStrategyPriority(address strategyAddress, address strategyPosition) external;

    function setStrategyMax(address strategyAddress, uint256 max) external;

    function addStrategy(
        address strategyAddress,
        uint256 max,
        address position
    ) external;

    function addStrategies(
        address[] calldata strategies,
        uint256[] calldata max,
        address position
    ) external;

    function deactivateStrategy(address strategyAddress) external;

    function emergencyDeactivateStrategy(address strategyAddress, address[] calldata assets) external;

    function dispatch() external;

    function withdraw(uint256 amountRequested) external returns (uint256 amountWithdrawn);

    function balance() external view returns (uint256 totalBalance);

    function balanceAvailable() external view returns (uint256 totalBalance, uint256 failedStrategies);

    function getNextStrategy(address strategy) external view returns (address);

    function recogniseRewards() external returns (uint256 allRewards, uint256 failedStrategies);

    function availableLimit() external view returns (uint256 amount);
}
