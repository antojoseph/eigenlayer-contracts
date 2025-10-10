// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./IProxyAdmin.sol";

interface IProtocolRegistryErrors {
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
}

interface IProtocolRegistryTypes {
    /**
     * @notice Configuration for a protocol deployment.
     * @param pausable Whether this deployment can be paused.
     * @param upgradeable Whether this deployment is upgradeable.
     * @param deprecated Whether this deployment is deprecated.
     */
    struct DeploymentConfig {
        bool pausable;
        bool upgradeable;
        bool deprecated;
    }

    /**
     * @notice Parameters describing a protocol deployment.
     * @param addr The address of the deployment (proxy address if upgradeable).
     * @param config The configuration for the deployment.
     */
    struct Deployment {
        address addr;
        DeploymentConfig config;
    }
}

interface IProtocolRegistryEvents is IProtocolRegistryTypes {
    /**
     * @notice Emitted when a deployment is shipped.
     * @param addr The address of the deployment.
     * @param semanticVersion The semantic version associated with the deployment.
     */
    event DeploymentShipped(address indexed addr, string semanticVersion);

    /**
     * @notice Emitted when a deployment is configured.
     * @param addr The address of the deployment.
     * @param config The configuration for the deployment.
     */
    event DeploymentConfigured(address indexed addr, DeploymentConfig config);

    /**
     * @notice Emitted when a deployment fails to pause.
     * @param addr The address of the deployment.
     */
    event PauseFailed(address indexed addr);
}

interface IProtocolRegistry is IProtocolRegistryErrors, IProtocolRegistryEvents {
    /**
     * @notice Initializes the ProtocolRegistry with the initial owner.
     * @param initialOwner The address to set as the initial owner.
     */
    function initialize(
        address initialOwner
    ) external;

    /**
     * @notice Ships a list of deployments and their corresponding implementations.
     * @dev Only callable by the owner.
     * @param deployments The deployments to ship.
     * @param contractName The name of the contract to ship.
     * @param semanticVersion The semantic version to ship.
     */
    function ship(
        Deployment[] calldata deployments,
        string calldata contractName,
        string calldata semanticVersion
    ) external;

    /**
     * @notice Configures a deployment.
     * @dev Only callable by the owner.
     * @param deploymentIndex The index of the deployment to configure.
     * @param config The configuration to set.
     */
    function configure(uint256 deploymentIndex, DeploymentConfig calldata config) external;

    /**
     * @notice Pauses all deployments that support pausing.
     * @dev Loops over all deployments and attempts to invoke `pauseAll()` on each contract that is marked as pausable.
     *      Silently ignores errors during calls for rapid pausing in emergencies. Owner only.
     */
    function pauseAll() external;

    /**
     * @notice Returns a deployment by name.
     * @param name The name of the deployment to get.
     * @return deployment The deployment.
     * @return implementation The implementation.
     */
    function getDeployment(
        string calldata name
    ) external view returns (Deployment memory deployment, address implementation);

    /**
     * @notice Returns all deployments.
     * @return names The names of the deployments.
     * @return deployments The deployments.
     * @return implementations The implementations.
     */
    function getAllDeployments()
        external
        view
        returns (string[] memory names, Deployment[] memory deployments, address[] memory implementations);

    /**
     * @notice Returns the total number of deployments.
     * @return The total number of deployments.
     */
    function totalDeployments() external view returns (uint256);

    /**
     * @notice Returns the proxy admin for the protocol.
     * @return The proxy admin for the protocol.
     */
    function PROXY_ADMIN() external view returns (IProxyAdmin);
}
