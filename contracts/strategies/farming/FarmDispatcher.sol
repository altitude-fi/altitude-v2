// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../common/Roles.sol";
import "../../libraries/uniswap-v3/TransferHelper.sol";
import "../../interfaces/internal/access/IIngress.sol";
import "../../interfaces/internal/vault/IVaultCore.sol";
import "../../interfaces/internal/strategy/farming/IFarmStrategy.sol";
import "../../interfaces/internal/strategy/farming/IFarmDispatcher.sol";

/**
 * @title FarmDispatcher Contract
 * @notice Contract to manage yield generation across multiple strategies
 * @author Altitude Labs
 **/

contract FarmDispatcher is Initializable, AccessControl, IFarmDispatcher {
    address public override vault;
    address public override asset;
    address public constant override STRATEGY_ZERO = address(0);
    uint256 public override availableLimit;

    mapping(address => Strategy) public override strategies;

    function initialize(address vaultAddress, address workingAsset, address admin) public virtual override initializer {
        _initialize(vaultAddress, workingAsset, admin);
    }

    function _initialize(address vaultAddress, address workingAsset, address admin) internal {
        if (vaultAddress == address(0)) {
            revert FD_VAULT_OR_OWNER();
        }
        if (workingAsset == address(0)) {
            revert FD_ZERO_ASSET();
        }
        if (admin == address(0)) {
            revert FD_VAULT_OR_OWNER();
        }

        vault = vaultAddress;
        asset = workingAsset;

        strategies[STRATEGY_ZERO] = Strategy(true, 0, 0, STRATEGY_ZERO, STRATEGY_ZERO);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Set a strategy at a position in the priority list
    /// @param strategyAddress Address of the strategy to set
    /// @param strategyPosition The address of the strategy that is to be related as a prev one
    function setStrategyPriority(
        address strategyAddress,
        address strategyPosition
    ) external override onlyRole(Roles.BETA) {
        Strategy memory strategy = strategies[strategyAddress];

        if (!strategy.active) {
            revert FD_INACTIVE_STRATEGY();
        }

        if (!strategies[strategyPosition].active) {
            revert FD_INACTIVE_STRATEGY_POSITION();
        }

        if (strategyAddress == strategyPosition) {
            revert FD_STRATEGY_PRIORITY_THE_SAME();
        }

        // Update surrounding strategy pointers
        strategies[strategy.prev].next = strategy.next;
        strategies[strategy.next].prev = strategy.prev;

        // Update current strategy pointers
        strategies[strategyAddress].prev = strategyPosition;
        strategies[strategyAddress].next = strategies[strategyPosition].next;

        // Update target position pointers
        strategies[strategies[strategyPosition].next].prev = strategyAddress;
        strategies[strategyPosition].next = strategyAddress;

        emit SetStrategyPiority(strategyAddress, strategyPosition);
    }

    /// @notice Set maximum amount the strategy can use to deposit into a farm provider
    /// @param strategyAddress Address of the strategy to set
    /// @param newMax Cap amount of the strategy
    function setStrategyMax(address strategyAddress, uint256 newMax) external override onlyRole(Roles.BETA) {
        if (strategyAddress == STRATEGY_ZERO) {
            revert FD_ZERO_STRATEGY_REMOVAL();
        }

        Strategy storage strategy = strategies[strategyAddress];

        if (!strategy.active) {
            revert FD_INACTIVE_STRATEGY();
        }

        uint256 oldMax = strategy.maxAmount;
        uint256 oldAvailable = oldMax - strategy.totalDeposit;
        uint256 deposited = IFarmStrategy(strategyAddress).balance();

        // Withdraw if updated cap has been exceeded
        if (deposited > newMax) {
            uint256 withdrawAmount = type(uint256).max;
            if (newMax != 0) {
                withdrawAmount = deposited - newMax;
            }
            IFarmStrategy(strategyAddress).withdraw(withdrawAmount);
            strategy.totalDeposit = newMax;
        } else {
            strategy.totalDeposit = deposited;
        }

        uint256 newAvailable = newMax - strategy.totalDeposit;

        if (oldAvailable > newAvailable) {
            availableLimit -= oldAvailable - newAvailable;
        } else {
            availableLimit += newAvailable - oldAvailable;
        }

        strategy.maxAmount = newMax;

        emit SetStrategyMax(strategyAddress, newMax);
    }

    /// @notice Introduce a new strategy
    /// @param strategyAddress Address of the new strategy to set
    /// @param max Cap amount of the strategy
    /// @param position The address of the strategy that is to be related as a prev one
    function addStrategy(address strategyAddress, uint256 max, address position) public override onlyRole(Roles.ALPHA) {
        // Check if strategy already exists and is active
        if (strategies[strategyAddress].active) {
            revert FD_STRATEGY_EXISTS();
        }

        // Prevent a new strategy linking to an inactive strategy
        if (!strategies[position].active) {
            revert FD_INACTIVE_STRATEGY_POSITION();
        }

        // Check if the strategy's farmDispatcher matches this contract
        if (IFarmStrategy(strategyAddress).farmDispatcher() != address(this)) {
            revert FD_INVALID_STRATEGY_DISPATCHER();
        }

        strategies[strategyAddress] = Strategy(true, max, 0, position, strategies[position].next);

        availableLimit += max;

        // Update pointers
        strategies[strategies[position].next].prev = strategyAddress;
        strategies[position].next = strategyAddress;

        emit AddStrategy(strategyAddress, max, position);
    }

    /// @notice Introduce multiple strategies
    /// @param farmStrategies Addresses of the new strategies
    /// @param max Cap amounts of the strategies
    /// @param position The address of the strategy that is to be related as a prev one to the first
    function addStrategies(
        address[] calldata farmStrategies,
        uint256[] calldata max,
        address position
    ) external override {
        if (farmStrategies.length != max.length) {
            revert FS_STRATEGIES_MISMATCH();
        }

        if (farmStrategies.length == 0) {
            revert FS_EMPTY_STRATEGIES();
        }

        uint256 strategiesLength = farmStrategies.length;
        for (uint256 i; i < strategiesLength; ) {
            addStrategy(farmStrategies[i], max[i], position);
            position = farmStrategies[i];

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Disable a strategy from the linkedlist
    /// @param strategyAddress Addresses of the strategy to be deactivated
    function deactivateStrategy(address strategyAddress) external override onlyRole(Roles.GAMMA) {
        Strategy storage strategy = strategies[strategyAddress];

        if (!strategy.active) {
            revert FD_INACTIVE_STRATEGY();
        }

        if (strategyAddress == STRATEGY_ZERO) {
            revert FD_ZERO_STRATEGY_REMOVAL();
        }

        availableLimit -= strategy.maxAmount - strategy.totalDeposit;

        strategy.active = false;
        strategies[strategy.prev].next = strategy.next;
        strategies[strategy.next].prev = strategy.prev;

        emit DeactivateStrategy(strategyAddress);
    }

    /// @notice Deposit any available funds into the strategies
    function dispatch() external override onlyRole(Roles.GAMMA) {
        uint256 amount = IERC20(asset).balanceOf(address(this));
        _dispatch(amount);

        emit Dispatch(amount);
    }

    /// @notice Function for depositing funds among the strategies based on the
    /// priority list and max cap. Deposit from the strategy with the highest priority down the list
    /// @param amount Amount to be deposited
    function _dispatch(uint256 amount) internal virtual {
        if (amount > 0) {
            // We start iterating from the zero strategy
            address strategyAddress = STRATEGY_ZERO;
            Strategy memory strategyData = strategies[strategyAddress];

            // While there is a next strategy
            while (strategyData.next != STRATEGY_ZERO && amount > 0) {
                // Make the next strategy our current strategy
                strategyAddress = strategyData.next;
                strategyData = strategies[strategyAddress];

                // Try to deposit into the current strategy
                if (strategyData.maxAmount > strategyData.totalDeposit) {
                    uint256 maxDeposit = strategyData.maxAmount - strategyData.totalDeposit;

                    uint256 toDeposit = maxDeposit >= amount ? amount : maxDeposit;

                    TransferHelper.safeApprove(asset, strategyAddress, toDeposit);

                    // Attempt deposit
                    try IFarmStrategy(strategyAddress).deposit(toDeposit) {
                        // Remainder to deposit in the next iteration
                        amount -= toDeposit;
                        availableLimit -= toDeposit;
                        strategies[strategyAddress].totalDeposit += toDeposit;
                    } catch (bytes memory lowLevelData) {
                        // Log a failed deposit
                        emit StrategyError(strategyAddress, lowLevelData);
                    }
                    // Removes approval
                    TransferHelper.safeApprove(asset, strategyAddress, 0);
                }
            }
        }
    }

    /// @notice Withdraws funds from the dispatcher, using strategies where needed
    /// @param amountRequested The amount to withdraw
    /// @return amountWithdrawn The amount actually withdrawn
    function withdraw(uint256 amountRequested) public virtual override returns (uint256 amountWithdrawn) {
        if (msg.sender != vault) {
            revert FD_ONLY_VAULT();
        }

        amountWithdrawn = _withdraw(amountRequested);
        if (amountWithdrawn > 0) {
            // Adjust the withdrawn amount if it is slightly higher
            if (amountWithdrawn > amountRequested) {
                amountWithdrawn = amountRequested;
            }

            // Transfer the amount to the vault
            TransferHelper.safeTransfer(asset, msg.sender, amountWithdrawn);
        }

        emit Withdraw(amountWithdrawn);
    }

    /// @notice Re-usable function for withdrawing funds from the strategies based on the
    /// priority list. Withdraw from the strategy with the lowest priority up the list.
    /// In case the dispatcher blance is enough to cover the requested amount, there is no withdraw from the strategies
    /// @param requested amount to withdraw
    /// @return withdrawn amount being withdrawn
    function _withdraw(uint256 requested) internal virtual returns (uint256 withdrawn) {
        // Check if there is an amount to withdraw
        if (requested > 0) {
            uint256 localDeposit = IERC20(asset).balanceOf(address(this));
            // First withdraw from localDeposit
            if (requested <= localDeposit) {
                withdrawn = requested;
            } else {
                withdrawn = localDeposit;

                // We interate the farming strategies list in reverse order
                uint256 toWithdraw = requested - withdrawn;
                address strategyAddr = strategies[STRATEGY_ZERO].prev;

                while (strategyAddr != STRATEGY_ZERO && toWithdraw > 0) {
                    Strategy storage strategy = strategies[strategyAddr];
                    // Attempt withdraw
                    try IFarmStrategy(strategyAddr).withdraw(toWithdraw) returns (uint256 strategyWithdrawn) {
                        withdrawn += strategyWithdrawn;

                        // Decrease totalDeposit to release capacity
                        if (strategy.totalDeposit > toWithdraw) {
                            availableLimit += toWithdraw;
                            strategy.totalDeposit -= toWithdraw;
                        } else {
                            availableLimit += strategy.totalDeposit;
                            strategy.totalDeposit = 0;
                        }

                        // Remainder to withdraw in the next iteration
                        if (requested > withdrawn) {
                            toWithdraw = requested - withdrawn;
                        } else {
                            toWithdraw = 0;
                        }
                    } catch (bytes memory lowLevelData) {
                        // Log a failed withdraw
                        emit StrategyError(strategyAddr, lowLevelData);
                    }

                    // Move to the previous strategy
                    strategyAddr = strategy.prev;
                }
            }
        }
    }

    /// @notice Return the amount that can be withdrawn at the moment
    /// @dev function will revert if any of the strategies reverts
    /// @return totalBalance in borrow asset
    function balance() public view virtual override returns (uint256 totalBalance) {
        totalBalance = IERC20(asset).balanceOf(address(this));
        Strategy memory strategy = strategies[STRATEGY_ZERO];
        while (strategy.next != STRATEGY_ZERO) {
            totalBalance += IFarmStrategy(strategy.next).balance();
            strategy = strategies[strategy.next];
        }
    }

    /// @notice Return the amount that can be withdrawn at the moment (skip reverts)
    /// @dev function will skip any of the strategies that revert
    /// @return availableBalance in borrow asset
    /// @return failedStrategies use bitwise AND operator to obtain from the result
    // the position of the strategy that has failed. 0 means no strategy has reverted
    function balanceAvailable()
        external
        view
        virtual
        override
        returns (uint256 availableBalance, uint256 failedStrategies)
    {
        uint256 strategyNumber = 0;
        availableBalance = IERC20(asset).balanceOf(address(this));
        Strategy memory strategy = strategies[STRATEGY_ZERO];
        while (strategy.next != STRATEGY_ZERO) {
            try IFarmStrategy(strategy.next).balanceAvailable() returns (uint256 strategyBalance) {
                availableBalance += strategyBalance;
            } catch {
                // Update failedStrategies
                // @dev if 1 and 3 failed, failedStrategies = 2^1 + 2^3 = 10
                failedStrategies += 2 ** strategyNumber;
            }

            strategyNumber += 1;
            strategy = strategies[strategy.next];
        }
    }

    /// @dev Used to iterate over the strategies list off-chain
    /// @param strategy The address of the strategy to get the next one
    /// @return next The address of the next strategy
    function getNextStrategy(address strategy) external view returns (address) {
        return strategies[strategy].next;
    }

    /// @notice Recognize rewards optimistically
    /// @dev function will skip any of the strategies that revert
    /// @return allRewards in borrow asset
    /// @return failedStrategies use bitwise AND operator to obtain from the result
    // the position of the strategy that has failed. 0 means no strategy has reverted
    function recogniseRewards() public virtual override returns (uint256 allRewards, uint256 failedStrategies) {
        uint256 strategyNumber = 0;
        Strategy memory strategy = strategies[STRATEGY_ZERO];
        while (strategy.next != STRATEGY_ZERO) {
            try IFarmStrategy(strategy.next).recogniseRewardsInBase() returns (uint256 rewards) {
                allRewards += rewards;
            } catch {
                // Update failedStrategies
                // @dev if 1 and 3 failed, failedStrategies = 2^1 + 2^3 = 10
                failedStrategies += 2 ** strategyNumber;
            }

            strategyNumber += 1;
            strategy = strategies[strategy.next];
        }

        emit RecogniseRewards(allRewards, failedStrategies);
    }
}
