// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../../../interfaces/internal/vault/IVaultStorage.sol";
import "../../../interfaces/internal/tokens/ISupplyToken.sol";
import "../../../interfaces/internal/tokens/IDebtToken.sol";
import "../../../interfaces/internal/misc/IBorrowVerifier.sol";

import "../../../libraries/types/VaultTypes.sol";
import "../../../libraries/types/CommonTypes.sol";
import "../../../libraries/types/HarvestTypes.sol";
import "../../../libraries/types/SupplyLossTypes.sol";

/**
 * @title VaultStorage
 * @dev Contract for keeping shared storage between Vault-like contracts
 * @author Altitude Labs
 **/

contract VaultStorage is IVaultStorage, ReentrancyGuard {
    /// @notice Validate if onlyOwner
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /// @notice Validate if onlyOwner and saving contract size
    function _onlyOwner() internal view virtual {
        if (msg.sender != owner) {
            revert VS_V1_ONLY_OWNER();
        }
    }

    constructor() {}

    /// @notice Owner of the vault(Registry)
    address public override owner;

    /** @notice Wrapped version of supply asset */
    ISupplyToken public override supplyToken;

    /** @notice Wrapped version of borrow asset */
    IDebtToken public override debtToken;

    /** @notice Supply asset */
    address public override supplyUnderlying;

    /** @notice Debt asset */
    address public override borrowUnderlying;

    /** @notice Address of the contract that allows borrowing on behalf */
    IBorrowVerifier public override borrowVerifier;

    /** @notice Block number user last deposited  */
    mapping(address => uint256) public userLastDepositBlock;

    /** @notice How much of their supply value a user can borrow up to */
    uint256 public override supplyThreshold;

    /** @notice Percentage value the vault aims to rebalance to in support of farming */
    uint256 public override targetThreshold;

    /** @notice Percentage value of borrows to supply value above which users can be liquidated */
    uint256 public override liquidationThreshold;

    /** @notice Swap strategy the vault is using for handling supply loss event */
    address public override swapStrategy;

    /** @notice Ingress control rules */
    address public override ingressControl;

    /** @notice Farm strategy the vault is currently using for interacting with the farm protocol */
    address public override activeFarmStrategy;

    /** @notice Lender strategy the vault is currently using for interacting with the lending protocol */
    address public override activeLenderStrategy;

    /** @notice Addresses (not)allowed to interact on behalf of a user */
    mapping(address => mapping(address => bool)) public override allowOnBehalfList;

    /** @notice Functions onBehalf validation is disabled for */
    mapping(bytes4 => bool) public override onBehalfFunctions;

    /** @notice Withdraw fee percent */
    uint256 public override withdrawFeeFactor;

    /** @notice How long the withdraw fee is applied (in blocks) */
    uint256 public override withdrawFeePeriod;

    /** @notice Implementation of harvest & supply loss snapshot logic */
    address internal snapshotManager;

    /** @notice Implementation of vault configuration logic */
    address public override configurableManager;

    /** @notice Harvest & supply loss snapshots */
    CommonTypes.SnapshotType[] public override snapshots;

    /** @notice User last commit/snapshot ids */
    mapping(address => uint256) public override userSnapshots;

    /// @notice Groomable parameters
    VaultTypes.GroomableConfig internal groomableStorage;

    /// @notice Liquidation parameters
    VaultTypes.LiquidatableConfig internal liquidatableStorage;

    /// @notice Harvest parameters
    HarvestTypes.HarvestStorage internal harvestStorage;

    /// @notice Supply loss parameters
    SupplyLossTypes.SupplyLossStorage internal supplyLossStorage;
}
