// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/utils/ShortStringsUpgradeable.sol";
import "../../interfaces/IProtocolRegistry.sol";

// 64 bytes remain, could also use a bitmap if more is needed.

abstract contract ProtocolRegistryStorage is IProtocolRegistry {
    /// @notice Returns the semantic version of the protocol.
    ShortString internal _semanticVersion;

    /// @notice Returns an append-only list of all deployment names.
    string[] internal _deploymentNames;
    /// @notice Returns the deployment ID for a given deployment name.
    mapping(bytes32 name => uint256 deploymentId) internal _deploymentIds;
    /// @notice Returns the deployment for a given deployment ID.
    mapping(uint256 deploymentId => Deployment deployment) internal _deployments;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;
}
