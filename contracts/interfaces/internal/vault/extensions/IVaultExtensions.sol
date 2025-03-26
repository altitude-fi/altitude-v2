// SPDX-License-Identifier: AGPL-3.0.
pragma solidity 0.8.28;

import "./configurable/IConfigurableVault.sol";
import "./groomable/IGroomableManager.sol";
import "./liquidatable/ILiquidatableManager.sol";
import "./snapshotable/ISnapshotableManager.sol";

/**
 * @author Altitude Protocol
 **/

interface IVaultExtensions is IConfigurableVaultV1, IGroomableManager, ILiquidatableManager, ISnapshotableManager {}
