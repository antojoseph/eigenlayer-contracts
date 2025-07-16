// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "../mixins/PermissionControllerMixin.sol";
import "../mixins/SemVerMixin.sol";
import "./ReleaseManagerStorage.sol";

contract ReleaseManager is Initializable, ReleaseManagerStorage, PermissionControllerMixin, SemVerMixin {
    /**
     *
     *                         INITIALIZING FUNCTIONS
     *
     */
    constructor(
        IPermissionController _permissionController,
        string memory _version
    ) PermissionControllerMixin(_permissionController) SemVerMixin(_version) {
        _disableInitializers();
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */

    /// @inheritdoc IReleaseManager
    function publishRelease(
        Namespace calldata namespace,
        Release calldata release
    ) external checkCanCall(namespace.authority) returns (uint256 releaseId) {
        Release[] storage releases = _namespaceReleases[_key(namespace)];

        require(bytes(_namespaceMetadataURI[_key(namespace)]).length != 0, MustPublishMetadataURI());
        require(release.upgradeByTime >= block.timestamp, InvalidUpgradeByTime());

        // New release id is the length of the array before this call.
        releaseId = releases.length;
        // Increment total releases for this namespace.
        releases.push();
        // Copy the release to storage.
        for (uint256 i = 0; i < release.artifacts.length; ++i) {
            releases[releaseId].artifacts.push(release.artifacts[i]);
        }
        releases[releaseId].upgradeByTime = release.upgradeByTime;

        emit ReleasePublished(namespace, releaseId, release);
    }

    /// @inheritdoc IReleaseManager
    function publishMetadataURI(
        Namespace calldata namespace,
        string calldata metadataURI
    ) external checkCanCall(namespace.authority) {
        require(bytes(metadataURI).length != 0, InvalidMetadataURI());
        _namespaceMetadataURI[_key(namespace)] = metadataURI;
        emit MetadataURIPublished(namespace, metadataURI);
    }

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @inheritdoc IReleaseManager
    function getTotalReleases(
        Namespace memory namespace
    ) public view returns (uint256) {
        return _namespaceReleases[_key(namespace)].length;
    }

    /// @inheritdoc IReleaseManager
    function getRelease(Namespace memory namespace, uint256 releaseId) external view returns (Release memory) {
        return _namespaceReleases[_key(namespace)][releaseId];
    }

    /// @inheritdoc IReleaseManager
    function getLatestRelease(
        Namespace memory namespace
    ) public view returns (uint256, Release memory) {
        Release[] storage releases = _namespaceReleases[_key(namespace)];
        uint256 latestReleaseId = releases.length - 1;
        return (latestReleaseId, releases[latestReleaseId]);
    }

    /// @inheritdoc IReleaseManager
    function getLatestUpgradeByTime(
        Namespace memory namespace
    ) external view returns (uint32) {
        Release[] storage releases = _namespaceReleases[_key(namespace)];
        uint256 latestReleaseId = releases.length - 1;
        return releases[latestReleaseId].upgradeByTime;
    }

    /// @inheritdoc IReleaseManager
    function isValidRelease(Namespace memory namespace, uint256 releaseId) external view returns (bool) {
        return releaseId == getTotalReleases(namespace) - 1;
    }

    /// @inheritdoc IReleaseManager
    function getMetadataURI(
        Namespace memory namespace
    ) external view returns (string memory) {
        return _namespaceMetadataURI[_key(namespace)];
    }

    /**
     * @notice Generates a unique key for storage
     */
    function _key(
        Namespace memory namespace
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(namespace.authority, namespace.id));
    }
}
