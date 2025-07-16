// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "src/contracts/core/ReleaseManager.sol";
import "src/test/utils/EigenLayerUnitTestSetup.sol";
import "src/contracts/interfaces/IReleaseManager.sol";
import "src/contracts/interfaces/IPermissionController.sol";

contract ReleaseManagerUnitTests is EigenLayerUnitTestSetup, IReleaseManagerErrors, IReleaseManagerEvents {
    using StdStyle for *;
    using ArrayLib for *;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint internal constant FUZZ_MAX_ARTIFACTS = 10;
    uint internal constant FUZZ_MAX_RELEASES = 20;

    /// -----------------------------------------------------------------------
    /// Contracts Under Test
    /// -----------------------------------------------------------------------

    ReleaseManager releaseManager;

    /// -----------------------------------------------------------------------
    /// Test Data
    /// -----------------------------------------------------------------------

    address defaultAVS = address(0x1234);
    Namespace defaultNamespace;
    Release defaultRelease;
    Artifact[] defaultArtifacts;

    /// -----------------------------------------------------------------------
    /// Setup
    /// -----------------------------------------------------------------------

    function setUp() public virtual override {
        EigenLayerUnitTestSetup.setUp();

        // Deploy ReleaseManager
        releaseManager = new ReleaseManager(permissionController, "1.0.0");

        // Setup default test data
        defaultNamespace = Namespace(defaultAVS, 0);

        defaultArtifacts.push(Artifact({digest: keccak256("artifact1"), registry: "https://example.com/artifact1"}));
        defaultArtifacts.push(Artifact({digest: keccak256("artifact2"), registry: "https://example.com/artifact2"}));

        defaultRelease.upgradeByTime = uint32(block.timestamp + 1 days);

        cheats.prank(defaultAVS);
        permissionController.setAppointee(defaultAVS, address(this), address(releaseManager), IReleaseManager.publishRelease.selector);

        cheats.prank(defaultAVS);
        releaseManager.publishMetadataURI(defaultNamespace, "https://example.com/metadata");
    }

    /// -----------------------------------------------------------------------
    /// Internal Helper Functions
    /// -----------------------------------------------------------------------

    function _createRelease(Artifact[] memory artifacts, uint32 upgradeByTime) internal pure returns (Release memory) {
        return Release({artifacts: artifacts, upgradeByTime: upgradeByTime});
    }

    function _createReleaseWithArtifacts(uint numArtifacts, uint32 upgradeByTime) internal pure returns (Release memory) {
        Artifact[] memory artifacts = new Artifact[](numArtifacts);
        for (uint i = 0; i < numArtifacts; i++) {
            artifacts[i] = Artifact({
                digest: keccak256(abi.encodePacked("artifact", i)),
                registry: string(abi.encodePacked("https://example.com/artifact", i))
            });
        }
        return _createRelease(artifacts, upgradeByTime);
    }

    function _publishRelease(Namespace memory namespace, Release memory release) internal returns (uint) {
        return releaseManager.publishRelease(namespace, release);
    }

    function _checkReleaseStorage(Namespace memory namespace, uint releaseId, Release memory expectedRelease) internal view {
        Release memory actualRelease = releaseManager.getRelease(namespace, releaseId);

        console.log("\nChecking Release Storage:".yellow());
        console.log("   Release ID: %d", releaseId);
        console.log("   Upgrade By Time: %d", actualRelease.upgradeByTime);
        console.log("   Number of Artifacts: %d", actualRelease.artifacts.length);

        assertEq(actualRelease.upgradeByTime, expectedRelease.upgradeByTime, "upgradeByTime mismatch");
        assertEq(actualRelease.artifacts.length, expectedRelease.artifacts.length, "artifacts length mismatch");

        for (uint i = 0; i < actualRelease.artifacts.length; i++) {
            assertEq(actualRelease.artifacts[i].digest, expectedRelease.artifacts[i].digest, "artifact digest mismatch");
            assertEq(actualRelease.artifacts[i].registry, expectedRelease.artifacts[i].registry, "artifact registry mismatch");
        }

        console.log("Success!".green().bold());
    }
}

contract ReleaseManagerUnitTests_Initialization is ReleaseManagerUnitTests {
    function test_constructor() public {
        // Test that constructor sets the correct values
        assertEq(address(releaseManager.permissionController()), address(permissionController), "permissionController not set correctly");
        assertEq(releaseManager.version(), "1.0.0", "version not set correctly");
    }
}

contract ReleaseManagerUnitTests_publishRelease is ReleaseManagerUnitTests {
    function test_revert_MustPublishMetadataURI() public {
        Namespace memory namespace = Namespace(defaultAVS, 1);

        cheats.prank(defaultAVS);
        vm.expectRevert(IReleaseManagerErrors.MustPublishMetadataURI.selector);
        releaseManager.publishRelease(namespace, defaultRelease);
    }

    function test_revert_InvalidUpgradeByTime() public {
        // Create release with past timestamp
        Release memory pastRelease = _createRelease(defaultArtifacts, uint32(block.timestamp - 1));

        vm.expectRevert(InvalidUpgradeByTime.selector);
        releaseManager.publishRelease(defaultNamespace, pastRelease);
    }

    function test_revert_upgradeByTimeEqualToNow() public {
        // Create release with current timestamp (edge case)
        Release memory currentRelease = _createRelease(defaultArtifacts, uint32(block.timestamp));

        // Should pass since requirement is >=
        uint releaseId = releaseManager.publishRelease(defaultNamespace, currentRelease);
        assertEq(releaseId, 0, "first release should have ID 0");
    }

    function test_revert_permissionDenied() public {
        // Remove permission
        cheats.prank(defaultAVS);
        permissionController.removeAppointee(defaultAVS, address(this), address(releaseManager), IReleaseManager.publishRelease.selector);

        vm.expectRevert(PermissionControllerMixin.InvalidPermissions.selector);
        releaseManager.publishRelease(defaultNamespace, defaultRelease);
    }

    function test_publishSingleRelease() public {
        // Check event emission
        vm.expectEmit(true, true, true, true, address(releaseManager));
        emit ReleasePublished(defaultNamespace, 0, defaultRelease);

        // Publish release
        uint releaseId = _publishRelease(defaultNamespace, defaultRelease);

        // Verify release ID
        assertEq(releaseId, 0, "first release should have ID 0");

        // Verify storage
        _checkReleaseStorage(defaultNamespace, releaseId, defaultRelease);

        // Verify total releases
        assertEq(releaseManager.getTotalReleases(defaultNamespace), 1, "should have 1 release");
    }

    function testFuzz_publishMultipleReleases(uint numReleases) public {
        numReleases = bound(numReleases, 1, FUZZ_MAX_RELEASES);

        for (uint i = 0; i < numReleases; i++) {
            Release memory release = _createReleaseWithArtifacts(2, uint32(block.timestamp + i + 1));

            // Check event
            vm.expectEmit(true, true, true, true, address(releaseManager));
            emit ReleasePublished(defaultNamespace, i, release);

            // Publish and verify ID
            uint releaseId = _publishRelease(defaultNamespace, release);
            assertEq(releaseId, i, "incorrect release ID");

            // Verify storage
            _checkReleaseStorage(defaultNamespace, releaseId, release);
        }

        // Verify total count
        assertEq(releaseManager.getTotalReleases(defaultNamespace), numReleases, "incorrect total releases");
    }

    function test_publishReleaseWithMultipleArtifacts() public {
        // Create release with many artifacts
        uint numArtifacts = 10;
        Release memory largeRelease = _createReleaseWithArtifacts(numArtifacts, uint32(block.timestamp + 1 days));

        // Publish
        uint releaseId = _publishRelease(defaultNamespace, largeRelease);

        // Verify all artifacts stored correctly
        _checkReleaseStorage(defaultNamespace, releaseId, largeRelease);
    }

    function test_publishReleaseEmptyArtifacts() public {
        // Create release with no artifacts
        Artifact[] memory emptyArtifacts = new Artifact[](0);
        Release memory emptyRelease = _createRelease(emptyArtifacts, uint32(block.timestamp + 1));

        // Should succeed
        uint releaseId = _publishRelease(defaultNamespace, emptyRelease);

        // Verify storage
        _checkReleaseStorage(defaultNamespace, releaseId, emptyRelease);
    }

    function testFuzz_publishReleaseDifferentNamespaces(uint32 namespaceId1, uint32 namespaceId2) public {
        vm.assume(namespaceId1 != namespaceId2);

        Namespace memory namespace1 = Namespace(defaultAVS, namespaceId1);
        Namespace memory namespace2 = Namespace(defaultAVS, namespaceId2);

        cheats.prank(namespace1.authority);
        releaseManager.publishMetadataURI(namespace1, "https://example.com/metadata");
        cheats.prank(namespace2.authority);
        releaseManager.publishMetadataURI(namespace2, "https://example.com/metadata");

        // Publish to first namespace
        uint releaseId1 = _publishRelease(namespace1, defaultRelease);
        assertEq(releaseId1, 0, "first release in namespace1 should be 0");

        // Publish to second namespace
        uint releaseId2 = _publishRelease(namespace2, defaultRelease);
        assertEq(releaseId2, 0, "first release in namespace2 should be 0");

        // Verify independent storage
        assertEq(releaseManager.getTotalReleases(namespace1), 1, "namespace1 should have 1 release");
        assertEq(releaseManager.getTotalReleases(namespace2), 1, "namespace2 should have 1 release");
    }
}

contract ReleaseManagerUnitTests_getTotalReleases is ReleaseManagerUnitTests {
    function test_getTotalReleases_noReleases() public view {
        uint total = releaseManager.getTotalReleases(defaultNamespace);
        assertEq(total, 0, "should have 0 releases initially");
    }

    function test_getTotalReleases_afterPublish() public {
        // Publish some releases
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(defaultNamespace, defaultRelease);

        uint total = releaseManager.getTotalReleases(defaultNamespace);
        assertEq(total, 3, "should have 3 releases");
    }

    function testFuzz_getTotalReleases_multiplePublishes(uint8 numReleases) public {
        for (uint i = 0; i < numReleases; i++) {
            Release memory release = _createReleaseWithArtifacts(1, uint32(block.timestamp + i + 1));
            _publishRelease(defaultNamespace, release);
        }

        uint total = releaseManager.getTotalReleases(defaultNamespace);
        assertEq(total, numReleases, "incorrect total releases");
    }

    function test_getTotalReleases_differentNamespaces() public {
        Namespace memory namespace2 = Namespace(defaultAVS, 1);

        cheats.prank(namespace2.authority);
        releaseManager.publishMetadataURI(namespace2, "https://example.com/metadata");

        // Publish to different namespaces
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(namespace2, defaultRelease);

        assertEq(releaseManager.getTotalReleases(defaultNamespace), 2, "namespace1 should have 2 releases");
        assertEq(releaseManager.getTotalReleases(namespace2), 1, "namespace2 should have 1 release");
    }
}

contract ReleaseManagerUnitTests_getRelease is ReleaseManagerUnitTests {
    function test_revert_getRelease_outOfBounds() public {
        // Try to get non-existent release
        vm.expectRevert(); // Array out of bounds
        releaseManager.getRelease(defaultNamespace, 0);
    }

    function test_getRelease_validId() public {
        // Publish a release
        uint releaseId = _publishRelease(defaultNamespace, defaultRelease);

        // Get and verify
        Release memory retrieved = releaseManager.getRelease(defaultNamespace, releaseId);
        assertEq(retrieved.upgradeByTime, defaultRelease.upgradeByTime, "upgradeByTime mismatch");
        assertEq(retrieved.artifacts.length, defaultRelease.artifacts.length, "artifacts length mismatch");
    }

    function testFuzz_getRelease_multipleReleases(uint8 numReleases, uint8 targetIndex) public {
        numReleases = uint8(bound(numReleases, 1, FUZZ_MAX_RELEASES));
        targetIndex = uint8(bound(targetIndex, 0, numReleases - 1));

        Release[] memory releases = new Release[](numReleases);

        // Publish multiple releases
        for (uint i = 0; i < numReleases; i++) {
            releases[i] = _createReleaseWithArtifacts(i + 1, uint32(block.timestamp + i + 1));
            _publishRelease(defaultNamespace, releases[i]);
        }

        // Get specific release and verify
        Release memory retrieved = releaseManager.getRelease(defaultNamespace, targetIndex);
        assertEq(retrieved.upgradeByTime, releases[targetIndex].upgradeByTime, "upgradeByTime mismatch");
        assertEq(retrieved.artifacts.length, releases[targetIndex].artifacts.length, "artifacts length mismatch");
    }

    function test_getRelease_afterMultiplePublishes() public {
        // Publish three different releases
        Release memory release1 = _createReleaseWithArtifacts(1, uint32(block.timestamp + 1));
        Release memory release2 = _createReleaseWithArtifacts(2, uint32(block.timestamp + 2));
        Release memory release3 = _createReleaseWithArtifacts(3, uint32(block.timestamp + 3));

        _publishRelease(defaultNamespace, release1);
        _publishRelease(defaultNamespace, release2);
        _publishRelease(defaultNamespace, release3);

        // Verify each can be retrieved correctly
        _checkReleaseStorage(defaultNamespace, 0, release1);
        _checkReleaseStorage(defaultNamespace, 1, release2);
        _checkReleaseStorage(defaultNamespace, 2, release3);
    }
}

contract ReleaseManagerUnitTests_getLatestRelease is ReleaseManagerUnitTests {
    function test_revert_getLatestRelease_noReleases() public {
        // Should revert with underflow
        vm.expectRevert();
        releaseManager.getLatestRelease(defaultNamespace);
    }

    function test_getLatestRelease_singleRelease() public {
        // Publish one release
        _publishRelease(defaultNamespace, defaultRelease);

        // Get latest
        (uint latestReleaseId, Release memory latest) = releaseManager.getLatestRelease(defaultNamespace);
        assertEq(latestReleaseId, 0, "latest release id should be 0");
        assertEq(latest.upgradeByTime, defaultRelease.upgradeByTime, "upgradeByTime mismatch");
        assertEq(latest.artifacts.length, defaultRelease.artifacts.length, "artifacts length mismatch");
    }

    function testFuzz_getLatestRelease_multipleReleases(uint8 numReleases) public {
        numReleases = uint8(bound(numReleases, 1, FUZZ_MAX_RELEASES));

        Release memory lastRelease;

        // Publish multiple releases
        for (uint i = 0; i < numReleases; i++) {
            lastRelease = _createReleaseWithArtifacts(i + 1, uint32(block.timestamp + i + 1));
            _publishRelease(defaultNamespace, lastRelease);
        }

        // Get latest and verify it's the last one published
        (uint latestReleaseId, Release memory latest) = releaseManager.getLatestRelease(defaultNamespace);
        assertEq(latestReleaseId, numReleases - 1, "latest release id should be the last one published");
        assertEq(latest.upgradeByTime, lastRelease.upgradeByTime, "upgradeByTime mismatch");
        assertEq(latest.artifacts.length, lastRelease.artifacts.length, "artifacts length mismatch");
    }

    function test_getLatestRelease_afterUpdates() public {
        // Publish initial release
        Release memory firstRelease = _createReleaseWithArtifacts(1, uint32(block.timestamp + 1));
        _publishRelease(defaultNamespace, firstRelease);

        // Verify latest is first
        (uint latestReleaseId, Release memory latest) = releaseManager.getLatestRelease(defaultNamespace);
        assertEq(latestReleaseId, 0, "latest release id should be 0");
        assertEq(latest.artifacts.length, 1, "should have 1 artifact");

        // Publish second release
        Release memory secondRelease = _createReleaseWithArtifacts(5, uint32(block.timestamp + 2));
        _publishRelease(defaultNamespace, secondRelease);

        // Verify latest is now second
        (latestReleaseId, latest) = releaseManager.getLatestRelease(defaultNamespace);
        assertEq(latestReleaseId, 1, "latest release id should be 1");
        assertEq(latest.artifacts.length, 5, "should have 5 artifacts");
    }
}

contract ReleaseManagerUnitTests_EdgeCases is ReleaseManagerUnitTests {
    function testFuzz_largeArtifactArray(uint16 numArtifacts) public {
        numArtifacts = uint16(bound(numArtifacts, 100, 1000));

        // Create release with many artifacts
        Release memory largeRelease = _createReleaseWithArtifacts(numArtifacts, uint32(block.timestamp + 1));

        // Publish
        uint releaseId = _publishRelease(defaultNamespace, largeRelease);

        // Verify storage
        Release memory retrieved = releaseManager.getRelease(defaultNamespace, releaseId);
        assertEq(retrieved.artifacts.length, numArtifacts, "artifacts not stored correctly");
    }

    function test_boundaryTimestamps() public {
        // Test with max uint32 timestamp
        Release memory maxTimeRelease = _createRelease(defaultArtifacts, type(uint32).max);
        uint releaseId = _publishRelease(defaultNamespace, maxTimeRelease);

        Release memory retrieved = releaseManager.getRelease(defaultNamespace, releaseId);
        assertEq(retrieved.upgradeByTime, type(uint32).max, "max timestamp not handled correctly");
    }

    function test_multipleNamespacesIndependence() public {
        // Create multiple namespaces
        Namespace memory namespace1 = Namespace(defaultAVS, 1);
        Namespace memory namespace2 = Namespace(address(0x5678), 0);

        cheats.prank(namespace1.authority);
        releaseManager.publishMetadataURI(namespace1, "https://example.com/metadata");
        cheats.prank(namespace2.authority);
        releaseManager.publishMetadataURI(namespace2, "https://example.com/metadata");

        // Grant permission for second authority
        cheats.prank(namespace2.authority);
        permissionController.setAppointee(namespace2.authority, address(this), address(releaseManager), IReleaseManager.publishRelease.selector);

        // Publish to each
        Release memory release1 = _createReleaseWithArtifacts(1, uint32(block.timestamp + 1));
        Release memory release2 = _createReleaseWithArtifacts(2, uint32(block.timestamp + 2));

        _publishRelease(namespace1, release1);
        _publishRelease(namespace2, release2);

        // Verify independence
        assertEq(releaseManager.getTotalReleases(namespace1), 1, "namespace1 should have 1 release");
        assertEq(releaseManager.getTotalReleases(namespace2), 1, "namespace2 should have 1 release");

        Release memory retrieved1 = releaseManager.getRelease(namespace1, 0);
        Release memory retrieved2 = releaseManager.getRelease(namespace2, 0);

        assertEq(retrieved1.artifacts.length, 1, "namespace1 release should have 1 artifact");
        assertEq(retrieved2.artifacts.length, 2, "namespace2 release should have 2 artifacts");
    }
}

contract ReleaseManagerUnitTests_getLatestUpgradeByTime is ReleaseManagerUnitTests {
    function test_revert_getLatestUpgradeByTime_noReleases() public {
        // Should revert with underflow
        vm.expectRevert();
        releaseManager.getLatestUpgradeByTime(defaultNamespace);
    }

    function test_getLatestUpgradeByTime_singleRelease() public {
        // Publish one release
        _publishRelease(defaultNamespace, defaultRelease);

        // Get latest upgrade by time
        uint upgradeByTime = releaseManager.getLatestUpgradeByTime(defaultNamespace);
        assertEq(upgradeByTime, defaultRelease.upgradeByTime, "upgradeByTime mismatch");
    }

    function test_getLatestUpgradeByTime_multipleReleases() public {
        // Publish multiple releases
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(defaultNamespace, defaultRelease);

        // Get latest upgrade by time
        uint upgradeByTime = releaseManager.getLatestUpgradeByTime(defaultNamespace);
        assertEq(upgradeByTime, defaultRelease.upgradeByTime, "upgradeByTime mismatch");
    }
}

contract ReleaseManagerUnitTests_isValidRelease is ReleaseManagerUnitTests {
    function test_revert_isValidRelease_noReleases() public {
        // Should revert with underflow
        vm.expectRevert();
        releaseManager.isValidRelease(defaultNamespace, 0);
    }

    function test_isValidRelease_singleRelease() public {
        // Publish one release
        _publishRelease(defaultNamespace, defaultRelease);

        // Check if the release is the latest
        bool isLatest = releaseManager.isValidRelease(defaultNamespace, 0);
        assertEq(isLatest, true, "release should be the latest");
    }

    function test_isValidRelease_multipleReleases() public {
        // Publish multiple releases
        _publishRelease(defaultNamespace, defaultRelease);
        _publishRelease(defaultNamespace, defaultRelease);

        // Check if the release is the latest
        bool isLatest = releaseManager.isValidRelease(defaultNamespace, 0);
        assertEq(isLatest, false, "first release should not be the latest");

        isLatest = releaseManager.isValidRelease(defaultNamespace, 1);
        assertEq(isLatest, true, "second release should be the latest");
    }
}

contract ReleaseManagerUnitTests_publishMetadataURI is ReleaseManagerUnitTests {
    function test_revert_InvalidMetadataURI() public {
        cheats.prank(defaultAVS);
        vm.expectRevert(IReleaseManagerErrors.InvalidMetadataURI.selector);
        releaseManager.publishMetadataURI(defaultNamespace, "");
    }

    function test_publishMetadataURI_Correctness() public {
        string memory registry = "https://example.com/metadata";
        cheats.expectEmit(true, true, true, true, address(releaseManager));
        emit MetadataURIPublished(defaultNamespace, registry);

        cheats.prank(defaultAVS);
        releaseManager.publishMetadataURI(defaultNamespace, registry);

        assertEq(releaseManager.getMetadataURI(defaultNamespace), registry, "metadata URI not set correctly");
    }
}
