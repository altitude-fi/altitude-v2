// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/**
 * @author Altitude Protocol
 **/

interface IInterestToken is IERC20Upgradeable, IERC20MetadataUpgradeable {
    event UserSnapshot(address account, uint256 _interestIndex);

    // Interest Token Errors
    error IT_ONLY_VAULT();
    error IT_MINT_MORE_THAN_SIZE();
    error IT_INTEREST_INDEX_OUT_OF_RANGE();
    error IT_TRANSFER_BETWEEN_THE_SAME_ADDRESSES();

    function MATH_UNITS() external view returns (uint256);

    function vault() external view returns (address);

    function underlying() external view returns (address);

    function activeLenderStrategy() external view returns (address);

    function userIndex(address user) external view returns (uint256);

    function interestIndex() external view returns (uint256);

    function initialize(
        string memory name,
        string memory symbol,
        address vaultAddress,
        address underlyingAsset,
        address lenderStrategy,
        uint256 mathUnits
    ) external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function vaultTransfer(address owner, address to, uint256 amount) external returns (bool);

    function setActiveLenderStrategy(address newStrategy) external;

    function snapshotUser(address account) external returns (uint256, uint256);

    function snapshot() external;

    function calcNewIndex() external view returns (uint256 index);

    function calcIndex(uint256 balanceOld, uint256 balanceNew) external view returns (uint256);

    function balanceStored(address account) external view returns (uint256);

    function setInterestIndex(uint256 newIndex) external;

    function setBalance(address account, uint256 newBalance, uint256 newIndex) external;

    function storedTotalSupply() external view returns (uint256);

    function balanceOfAt(address account, uint256 snapshotId) external view returns (uint256);
}
