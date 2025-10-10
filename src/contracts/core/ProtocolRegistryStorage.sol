// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/utils/ShortStringsUpgradeable.sol";
import "../interfaces/IProtocolRegistry.sol";

// 64 bytes remain, could also use a bitmap if more is needed.

abstract contract ProtocolRegistryStorage is IProtocolRegistry {
    /// @notice Returns an append-only historical record of all semantic version identifiers for the protocol's deployments.
    /// @dev Each entry corresponds to a version used for a deployment in the order they occurred.
    ///      The latest element is the semantic version for the most recent deployment.
    ShortString[] internal _semanticVersions;

    /// @notice Returns an append-only list of all deployment names.
    string[] internal _deploymentNames;

    /// @notice Returns the deployment ID for a given deployment name.
    mapping(bytes32 name => uint256 deploymentId) internal _deploymentIds;

    /// @notice Returns the deployment for a given deployment ID.
    mapping(uint256 deploymentId => Deployment deployment) internal _deployments;

    /// @notice Returns the implementations for a given deployment.
    /// @dev We use a nested list to support split-contract patterns.
    mapping(address proxy => address[][] implementations) internal _implementations;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
