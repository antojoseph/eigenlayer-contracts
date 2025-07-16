// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IReleaseManagerErrors {
    /// @notice Thrown when a metadata URI must be published before publishing a release.
    error MustPublishMetadataURI();

    /// @notice Thrown when the upgrade by time is in the past.
    error InvalidUpgradeByTime();

    /// @notice Thrown when the metadata URI is empty.
    error InvalidMetadataURI();
}

interface IReleaseManagerTypes {
    /// @notice Namespace for organizing releases
    /// @param authority The address that controls permissions for this namespace
    /// @param id Arbitrary identifier
    struct Namespace {
        address authority;
        uint32 id;
    }

    /// @notice Represents a software artifact with its digest and registry URL.
    /// @param digest The hash digest of the artifact.
    /// @param registry Where the artifact can be found.
    struct Artifact {
        bytes32 digest;
        string registry;
    }

    /// @notice Represents a release containing multiple artifacts and an upgrade deadline.
    /// @param artifacts Array of artifacts included in this release.
    /// @param upgradeByTime Timestamp by which operators must upgrade to this release.
    struct Release {
        Artifact[] artifacts;
        uint32 upgradeByTime;
    }
}

interface IReleaseManagerEvents is IReleaseManagerTypes {
    /// @notice Emitted when a new release is published.
    /// @param namespace The namespace this release belongs to.
    /// @param releaseId The id of the release that was published.
    /// @param release The release that was published.
    event ReleasePublished(Namespace indexed namespace, uint256 indexed releaseId, Release release);

    /// @notice Emitted when a metadata URI is published.
    /// @param namespace The namespace this metadata URI belongs to.
    /// @param metadataURI The metadata URI that was published.
    event MetadataURIPublished(Namespace indexed namespace, string metadataURI);
}

interface IReleaseManager is IReleaseManagerErrors, IReleaseManagerEvents {
    /**
     *
     *                         WRITE FUNCTIONS
     *
     */

    /// @notice Publishes a new release.
    /// @param namespace The namespace this release belongs to.
    /// @param release The release that was published.
    /// @return releaseId The index of the newly published release.
    function publishRelease(
        Namespace calldata namespace,
        Release calldata release
    ) external returns (uint256 releaseId);

    /// @notice Publishes a metadata URI.
    /// @param namespace The namespace this metadata URI belongs to.
    /// @param metadataURI The metadata URI that was published.
    function publishMetadataURI(Namespace calldata namespace, string calldata metadataURI) external;

    /**
     *
     *                         VIEW FUNCTIONS
     *
     */

    /// @notice Returns the total number of releases for a namespace.
    /// @param namespace The namespace to query.
    /// @return The number of releases.
    function getTotalReleases(
        Namespace memory namespace
    ) external view returns (uint256);

    /// @notice Returns a specific release by index.
    /// @param namespace The namespace to query.
    /// @param releaseId The id of the release to get.
    /// @return The release at the specified index.
    function getRelease(Namespace memory namespace, uint256 releaseId) external view returns (Release memory);

    /// @notice Returns the latest release for a namespace.
    /// @param namespace The namespace to query.
    /// @return The id of the latest release.
    /// @return The latest release.
    function getLatestRelease(
        Namespace memory namespace
    ) external view returns (uint256, Release memory);

    /// @notice Returns the upgrade by time for the latest release.
    /// @param namespace The namespace to query.
    /// @return The upgrade by time for the latest release.
    function getLatestUpgradeByTime(
        Namespace memory namespace
    ) external view returns (uint32);

    /// @notice Returns true if the release is the latest release, false otherwise.
    /// @param namespace The namespace to query.
    /// @param releaseId The id of the release to check.
    /// @return True if the release is the latest release, false otherwise.
    function isValidRelease(Namespace memory namespace, uint256 releaseId) external view returns (bool);

    /// @notice Returns the metadata URI for a namespace.
    /// @param namespace The namespace to query.
    /// @return The metadata URI for the namespace.
    function getMetadataURI(
        Namespace memory namespace
    ) external view returns (string memory);
}
