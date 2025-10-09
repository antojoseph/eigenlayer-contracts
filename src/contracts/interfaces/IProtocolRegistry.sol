// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IProtocolRegistryErrors {
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
}

interface IProtocolRegistryTypes {
    /**
     * @notice Configuration for a protocol deployment.
     * @param pausable Whether this deployment can be paused.
     * @param upgradeable Whether this deployment is upgradeable.
     * @param splitContract Whether this deployment uses a split-contract pattern (two implementations).
     * @param deprecated Whether this deployment is deprecated.
     */
    struct DeploymentConfig {
        bool pausable;
        bool upgradeable;
        bool splitContract;
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
     * @param implementations The implementation addresses for the deployment.
     * @param semanticVersion The semantic version associated with the deployment.
     */
    event DeploymentShipped(address indexed addr, address[] implementations, string semanticVersion);

    /**
     * @notice Emitted when a deployment is configured.
     * @param addr The address of the deployment.
     * @param config The configuration for the deployment.
     */
    event DeploymentConfigured(address indexed addr, DeploymentConfig config);
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
     * @notice Ships a deployment and it's corresponding implementations.
     * @dev Only callable by the owner.
     * @param deployment The deployment to ship.
     * @param implementations The implementations to ship.
     * @param semanticVersion The semantic version to ship.
     */
    function ship(
        Deployment calldata deployment,
        address[] calldata implementations,
        string calldata semanticVersion
    ) external;

    /**
     * @notice Ships a list of deployments and their corresponding implementations.
     * @dev Only callable by the owner.
     * @param deployments The deployments to ship.
     * @param implementations The implementations to ship.
     * @param semanticVersion The semantic version to ship.
     */
    function ship(
        Deployment[] calldata deployments,
        address[][] calldata implementations,
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
     * @notice Returns the semantic version string for the latest deployment.
     * @return The semantic version string associated with the latest deployment.
     */
    function latestVersion() external view returns (string memory);

    /**
     * @notice Returns the major version string for the latest deployment.
     * @return The major version string associated with the latest deployment.
     */
    function latestMajorVersion() external view returns (string memory);
}
