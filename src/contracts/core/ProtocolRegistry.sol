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
    constructor() {
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
        _semanticVersions.push(semanticVersion.toShortString());
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
        _semanticVersions.push(semanticVersion.toShortString());
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
                // Attempt to call pauseAll; if it fails, continue to the next deployment.
                // This ensures a single failure does not prevent us from pausing others in a timely manner.
                try IPausable(deployment.addr).pauseAll() {}
                catch {
                    // Emit an event for faster debugging.
                    emit PauseFailed(deployment.addr);
                }
            }
        }
    }

    /**
     *
     *                             HELPER FUNCTIONS
     *
     */

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

    /**
     *
     *                              VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IProtocolRegistry
    function getDeployment(
        string calldata name
    ) external view returns (Deployment memory) {
        return _deployments[_deploymentIds[keccak256(bytes(name))]];
    }

    /// @inheritdoc IProtocolRegistry
    function getAllDeployments() external view returns (string[] memory names, Deployment[] memory deployments) {
        uint256 length = totalDeployments();
        names = new string[](length);
        deployments = new Deployment[](length);
        for (uint256 i = 0; i < length; ++i) {
            names[i] = _deploymentNames[i];
            deployments[i] = _deployments[i];
        }
    }

    /// @inheritdoc IProtocolRegistry
    function totalDeployments() public view returns (uint256) {
        return _deploymentNames.length;
    }

    /// @inheritdoc IProtocolRegistry
    function latestVersion() public view returns (string memory) {
        unchecked {
            return _semanticVersions[_deploymentNames.length - 1].toString();
        }
    }

    /// @inheritdoc IProtocolRegistry
    function latestMajorVersion() external view returns (string memory) {
        bytes memory v = bytes(latestVersion());
        return string(bytes.concat(v[0]));
    }
}
