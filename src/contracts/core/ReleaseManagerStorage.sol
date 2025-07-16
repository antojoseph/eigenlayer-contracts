// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../interfaces/IReleaseManager.sol";

abstract contract ReleaseManagerStorage is IReleaseManager {
    // Mutables

    /// @notice Returns an array of releases for a given namespace.
    mapping(bytes32 namespaceKey => Release[]) internal _namespaceReleases;

    /// @notice Returns the metadata URI for a given namespace.
    mapping(bytes32 namespaceKey => string metadataURI) internal _namespaceMetadataURI;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
