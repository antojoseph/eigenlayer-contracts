// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./IProxyAdmin.sol";

interface IProtocolRegistryErrors {
    /// @notice Thrown when two array parameters have mismatching lengths.
    error InputArrayLengthMismatch();
    /// @notice Thrown when an index is out of bounds.
    error OutOfBounds();
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
}

interface IProtocolRegistryEvents is IProtocolRegistryTypes {
    /**
     * @notice Emitted when a deployment is shipped.
     * @param addr The address of the deployment.
     * @param config The configuration for the deployment.
     * @param semanticVersion The semantic version associated with the deployment.
     */
    event DeploymentShipped(address indexed addr, DeploymentConfig config, string semanticVersion);

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
     * @notice Initializes the ProtocolRegistry with the initial admin.
     * @param initialAdmin The address to set as the initial admin.
     * @param pauserMultisig The address to set as the pauser multisig.
     */
    function initialize(address initialAdmin, address pauserMultisig) external;

    /**
     * @notice Ships a list of deployments and their corresponding implementations.
     * @dev Only callable by the admin.
     * @param addresses The addresses of the deployments to ship.
     * @param configs The configurations of the deployments to ship.
     * @param contractNames The names of the contracts to ship.
     * @param semanticVersion The semantic version to ship.
     */
    function ship(
        address[] calldata addresses,
        DeploymentConfig[] calldata configs,
        string[] calldata contractNames,
        string calldata semanticVersion
    ) external;

    /**
     * @notice Configures a deployment.
     * @dev Only callable by the admin.
     * @param addr The address of the deployment to configure.
     * @param config The configuration to set.
     */
    function configure(address addr, DeploymentConfig calldata config) external;

    /**
     * @notice Pauses all deployments that support pausing.
     * @dev Loops over all deployments and attempts to invoke `pauseAll()` on each contract that is marked as pausable.
     *      Silently ignores errors during calls for rapid pausing in emergencies. Pauser role only.
     */
    function pauseAll() external;

    /**
     * @notice Returns a deployment by name.
     * @param name The name of the deployment to get.
     * @return address The address of the deployment.
     */
    function getAddress(
        string calldata name
    ) external view returns (address);

    /**
     * @notice Returns a deployment by name.
     * @param name The name of the deployment to get.
     * @return addr The address.
     * @return implementation The implementation.
     * @return config The configuration.
     */
    function getDeployment(
        string calldata name
    ) external view returns (address addr, address implementation, DeploymentConfig memory config);

    /**
     * @notice Returns all deployments.
     * @return names The names of the deployments.
     * @return addresses The addresses.
     * @return implementations The implementations.
     * @return configs The configurations.
     */
    function getAllDeployments()
        external
        view
        returns (
            string[] memory names,
            address[] memory addresses,
            address[] memory implementations,
            DeploymentConfig[] memory configs
        );

    /**
     * @notice Returns the total number of deployments.
     * @return The total number of deployments.
     */
    function totalDeployments() external view returns (uint256);

    /**
     * @notice Returns the pauser role for the protocol.
     * @return The pauser role for the protocol.
     */
    function PAUSER_ROLE() external view returns (bytes32);

    /**
     * @notice Returns the proxy admin for the protocol.
     * @return The proxy admin for the protocol.
     */
    function PROXY_ADMIN() external view returns (IProxyAdmin);
}
