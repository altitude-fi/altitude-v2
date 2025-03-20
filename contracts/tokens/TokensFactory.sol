// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../tokens/SupplyToken.sol";
import "../tokens/DebtToken.sol";
import "../common/ProxyInitializable.sol";
import "../interfaces/internal/tokens/ITokensFactory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokensFactory
 * @dev Contract for deploying a pair of interest bearing tokens (supply & debt) for a vault
 * @author Altitude Labs
 **/

contract TokensFactory is Ownable, ITokensFactory {
    /** @notice address allowed to create token pairs */
    address public override registry;

    /** @notice address of the upgradable debt token implementation */
    address public override debtTokenImplementation;

    /** @notice address of the upgradable supply token implementation */
    address public override supplyTokenImplementation;

    /** @notice address allowed to upgrade vaults */
    address public override proxyAdmin;

    constructor(address newProxyAdmin) {
        if (newProxyAdmin == address(0)) {
            revert TF_ZERO_ADDRESS();
        }

        proxyAdmin = newProxyAdmin;
        emit UpdateProxyAdmin(newProxyAdmin);
    }

    /// @notice Set a new registy to rule the tokens creation
    /// @param newRegistry The address of the registry
    function setRegistry(address newRegistry) external override onlyOwner {
        registry = newRegistry;
        emit SetRegistry(newRegistry);
    }

    /// @notice Set a new supply token implementation to be used from now on
    /// @param implentation The address of the supply implementation
    function setSupplyTokenImplementation(address implentation) external override onlyOwner {
        supplyTokenImplementation = implentation;
        emit SetSupplyTokenImplementation(implentation);
    }

    /// @notice Set a new debt token implementation to be used from now on
    /// @param implentation The address of the debt implementation
    function setDebtTokenImplementation(address implentation) external override onlyOwner {
        debtTokenImplementation = implentation;
        emit SetDebtTokenImplementation(implentation);
    }

    /// @notice Set who can upgrade vaults implementation
    /// @param newProxyAdmin The address allowed to upgrade vaults
    function setProxyAdmin(address newProxyAdmin) external override onlyOwner {
        if (newProxyAdmin == address(0)) {
            revert TF_ZERO_ADDRESS();
        }

        proxyAdmin = newProxyAdmin;
        emit UpdateProxyAdmin(newProxyAdmin);
    }

    /// @notice Deploy SupplyToken and DebtToken pair for a newly created vault
    /// @param vault The newly created vault
    /// @param supplyAsset The underlying asset of the SupplyToken
    /// @param borrowAsset The underlying asset of the DebtToken
    /// @param lenderStrategy The active lender strategy the tokens should interact with in order to track the interest
    /// @return supplyTokenAddress The address of the supply asset wrapper
    /// @return debtTokenAddress The address of the borrow asset wrapper
    function createPair(
        address vault,
        address supplyAsset,
        address borrowAsset,
        uint256 supplyMathUnits,
        uint256 debtMathUnits,
        address lenderStrategy
    ) external override returns (address supplyTokenAddress, address debtTokenAddress) {
        if (msg.sender != registry) {
            revert TF_ONLY_REGISTRY();
        }

        string memory name = string(
            abi.encodePacked(IERC20Metadata(supplyAsset).symbol(), IERC20Metadata(borrowAsset).symbol())
        );

        supplyTokenAddress = _deployToken(
            supplyTokenImplementation,
            name,
            " v1 Supply Token",
            "v1S",
            vault,
            supplyAsset,
            lenderStrategy,
            supplyMathUnits
        );

        debtTokenAddress = _deployToken(
            debtTokenImplementation,
            name,
            " v1 Debt Token",
            "v1D",
            vault,
            borrowAsset,
            lenderStrategy,
            debtMathUnits
        );
    }

    function _deployToken(
        address implementation,
        string memory name,
        string memory nameInitials,
        string memory symbolInitials,
        address vault,
        address asset,
        address strategy,
        uint256 units
    ) internal returns (address) {
        ProxyInitializable tokenProxy = new ProxyInitializable();
        tokenProxy.initialize(
            proxyAdmin,
            implementation,
            abi.encodeWithSelector(
                IInterestToken.initialize.selector,
                string(abi.encodePacked("Altitude Ethereum ", name, nameInitials)),
                string(abi.encodePacked("ALTI", name, symbolInitials)),
                vault,
                asset,
                strategy,
                units
            )
        );

        return address(tokenProxy);
    }
}
