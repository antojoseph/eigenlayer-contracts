// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../interfaces/IPausable.sol";
import "./storage/ProtocolRegistryStorage.sol";

contract ProtocolRegistry is Initializable, OwnableUpgradeable, ProtocolRegistryStorage {
    using ShortStringsUpgradeable for *;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    /**
     *
     *                         INITIALIZING FUNCTIONS
     *
     */
    constructor(
        IProxyAdmin proxyAdmin
    ) ProtocolRegistryStorage(proxyAdmin) {
        _disableInitializers();
    }

    /// @inheritdoc IProtocolRegistry
    function initialize(
        address initialOwner
    ) external initializer {
        _transferOwnership(initialOwner);
    }

    /**
     *
     *                         INITIALIZING FUNCTIONS
     *
     */

    /// @inheritdoc IProtocolRegistry
    function ship(
        address[] calldata addresses,
        DeploymentConfig[] calldata configs,
        string[] calldata names,
        string calldata semanticVersion
    ) external onlyOwner {
        // Update the semantic version.
        _updateSemanticVersion(semanticVersion);
        for (uint256 i = 0; i < addresses.length; ++i) {
            // Append each provided
            _appendDeployment(addresses[i], configs[i], names[i], semanticVersion);
        }
    }

    /// @inheritdoc IProtocolRegistry
    function configure(address addr, DeploymentConfig calldata config) external onlyOwner {
        // Update the config
        _deploymentConfigs[addr] = config;
        // Emit the event.
        emit DeploymentConfigured(addr, config);
    }

    /// @inheritdoc IProtocolRegistry
    function pauseAll() external onlyOwner {
        uint256 length = totalDeployments();
        // Iterate over all stored deployments.
        for (uint256 i = 0; i < length; ++i) {
            (, address addr) = _deployments.at(i);
            DeploymentConfig memory config = _deploymentConfigs[addr];
            // Only attempt to pause deployments marked as pausable.
            if (config.pausable && !config.deprecated) {
                IPausable(addr).pauseAll();
            }
        }
    }

    /**
     *
     *                             HELPER FUNCTIONS
     *
     */

    /// @dev Updates the semantic version of the protocol.
    function _updateSemanticVersion(
        string calldata semanticVersion
    ) internal {
        _semanticVersion = semanticVersion.toShortString();
    }

    /// @dev Appends a deployment.
    function _appendDeployment(
        address addr,
        DeploymentConfig calldata config,
        string calldata name,
        string calldata semanticVersion
    ) internal {
        // Store name => address mapping
        _deployments.set({key: _unwrap(name.toShortString()), value: addr});
        // Store deployment config
        _deploymentConfigs[addr] = config;
        // Emit the events.
        emit DeploymentShipped(addr, config, semanticVersion);
    }

    /// @dev Fetches the implementation for a deployment if it's upgradeable.
    /// Otherwise, returns the deployment address.
    function _getImplementation(address addr, DeploymentConfig memory config) internal view returns (address) {
        if (config.upgradeable) {
            return PROXY_ADMIN.getProxyImplementation(addr);
        }
        return addr;
    }

    /// @dev Unwraps a ShortString to a uint256.
    function _unwrap(
        ShortString shortString
    ) internal pure returns (uint256) {
        return uint256(ShortString.unwrap(shortString));
    }

    /// @dev Wraps a uint256 to a ShortString.
    function _wrap(
        uint256 shortString
    ) internal pure returns (ShortString) {
        return ShortString.wrap(bytes32(shortString));
    }

    /**
     *
     *                              VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IProtocolRegistry
    function getAddress(
        string calldata name
    ) external view returns (address) {
        return _deployments.get(_unwrap(name.toShortString()));
    }

    /// @inheritdoc IProtocolRegistry
    function getDeployment(
        string calldata name
    ) external view returns (address addr, address implementation, DeploymentConfig memory config) {
        addr = _deployments.get(_unwrap(name.toShortString()));
        implementation = _getImplementation(addr, config);
        config = _deploymentConfigs[addr];
        return (addr, implementation, config);
    }

    /// @inheritdoc IProtocolRegistry
    function getAllDeployments()
        external
        view
        returns (
            string[] memory names,
            address[] memory addresses,
            address[] memory implementations,
            DeploymentConfig[] memory configs
        )
    {
        uint256 length = totalDeployments();
        names = new string[](length);
        addresses = new address[](length);
        implementations = new address[](length);
        configs = new DeploymentConfig[](length);

        for (uint256 i = 0; i < length; ++i) {
            (uint256 nameShortString, address addr) = _deployments.at(i);
            names[i] = ShortString.wrap(bytes32(nameShortString)).toString();
            addresses[i] = addr;
            configs[i] = _deploymentConfigs[addr];
            implementations[i] = _getImplementation(addr, configs[i]);
        }

        return (names, addresses, implementations, configs);
    }

    /// @inheritdoc IProtocolRegistry
    function totalDeployments() public view returns (uint256) {
        return _deployments.length();
    }
}
