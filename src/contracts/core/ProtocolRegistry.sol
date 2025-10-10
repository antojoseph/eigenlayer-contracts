// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "../interfaces/IPausable.sol";
import "./ProtocolRegistryStorage.sol";

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
        string calldata semanticVersion
    ) external onlyOwner {
        // Update the semantic version.
        _semanticVersions.push(semanticVersion.toShortString());
        // Append the single deployment.
        _appendDeployment(deployment, implementations, semanticVersion);
    }

    /// @inheritdoc IProtocolRegistry
    function ship(
        Deployment[] calldata deployments,
        address[][] calldata implementations,
        string calldata semanticVersion
    ) external onlyOwner {
        // Update the semantic version.
        _semanticVersions.push(semanticVersion.toShortString());
        for (uint256 i = 0; i < deployments.length; ++i) {
            // Append each provided deployment.
            _appendDeployment(deployments[i], implementations[i], semanticVersion);
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
        uint256 totalDeployments = _deployments.length;
        // Iterate over all stored deployments
        for (uint256 i = 0; i < totalDeployments; ++i) {
            Deployment storage deployment = _deployments[i];
            // Only attempt to pause deployments marked as pausable
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
        string calldata semanticVersion
    ) internal {
        // TODO: Prevent duplicates

        // Append the deployment.
        _deployments.push(deployment);
        // Append the implementations for the deployment.
        _implementations[deployment.addr].push(implementations);
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
    function latestVersion() public view returns (string memory) {
        unchecked {
            return _semanticVersions[_deployments.length - 1].toString();
        }
    }

    /// @inheritdoc IProtocolRegistry
    function latestMajorVersion() external view returns (string memory) {
        bytes memory v = bytes(latestVersion());
        return string(bytes.concat(v[0]));
    }
}
