// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../interfaces/IPausable.sol";
import "./storage/ProtocolRegistryStorage.sol";

contract ProtocolRegistry is Initializable, OwnableUpgradeable, ProtocolRegistryStorage {
    using ShortStringsUpgradeable for *;

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
        Deployment calldata deployment,
        address[] calldata implementations,
        string calldata name,
        string calldata semanticVersion
    ) external onlyOwner {
        // Update the semantic version.
        _updateSemanticVersion(semanticVersion);
        // Append the single deployment.
        _appendDeployment(deployment, implementations, name, semanticVersion);
    }

    /// @inheritdoc IProtocolRegistry
    function ship(
        Deployment[] calldata deployments,
        address[][] calldata implementations,
        string calldata name,
        string calldata semanticVersion
    ) external onlyOwner {
        // Update the semantic version.
        _updateSemanticVersion(semanticVersion);
        for (uint256 i = 0; i < deployments.length; ++i) {
            // Append each provided deployment.
            _appendDeployment(deployments[i], implementations[i], name, semanticVersion);
        }
    }

    /// @inheritdoc IProtocolRegistry
    function configure(uint256 deploymentIndex, DeploymentConfig calldata config) external onlyOwner {
        // Create a storage pointer for so we only read once.
        Deployment storage deployment = _deployments[deploymentIndex];
        // Update the deployment config.
        deployment.config = config;
        // Emit the event.
        emit DeploymentConfigured(deployment.addr, config);
    }

    /// @inheritdoc IProtocolRegistry
    function pauseAll() external onlyOwner {
        uint256 length = totalDeployments();
        // Iterate over all stored deployments.
        for (uint256 i = 0; i < length; ++i) {
            Deployment storage deployment = _deployments[i];
            // Only attempt to pause deployments marked as pausable.
            if (deployment.config.pausable) {
                IPausable(deployment.addr).pauseAll();
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

    /// @dev Appends a deployment and it's corresponding implementations.
    function _appendDeployment(
        Deployment calldata deployment,
        address[] calldata implementations,
        string calldata name,
        string calldata semanticVersion
    ) internal {
        // TODO: Prevent duplicates

        uint256 deploymentId = totalDeployments();

        // Store the deployment.
        _deployments[deploymentId] = deployment;
        // Store the deployment ID.
        _deploymentIds[keccak256(bytes(name))] = deploymentId;
        // Append the deployment name.
        _deploymentNames.push(name);

        // Emit the events.
        emit DeploymentShipped(deployment.addr, implementations, semanticVersion);
        emit DeploymentConfigured(deployment.addr, deployment.config);
    }

    /// @dev Fetches the implementation for a deployment if it's upgradeable.
    /// Otherwise, returns the deployment address.
    function _getImplementation(
        Deployment memory deployment
    ) internal view returns (address) {
        return deployment.config.upgradeable ? PROXY_ADMIN.getProxyImplementation(deployment.addr) : deployment.addr;
    }

    /**
     *
     *                              VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IProtocolRegistry
    function getDeployment(
        string calldata name
    ) external view returns (Deployment memory deployment, address implementation) {
        deployment = _deployments[_deploymentIds[keccak256(bytes(name))]];
        implementation = _getImplementation(deployment);
    }

    /// @inheritdoc IProtocolRegistry
    function getAllDeployments()
        external
        view
        returns (string[] memory names, Deployment[] memory deployments, address[] memory implementations)
    {
        uint256 length = totalDeployments();
        names = new string[](length);
        deployments = new Deployment[](length);
        for (uint256 i = 0; i < length; ++i) {
            names[i] = _deploymentNames[i];
            deployments[i] = _deployments[i];
            implementations[i] = _getImplementation(deployments[i]);
        }
    }

    /// @inheritdoc IProtocolRegistry
    function totalDeployments() public view returns (uint256) {
        return _deploymentNames.length;
    }
}
