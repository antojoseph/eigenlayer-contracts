// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "src/contracts/core/ProtocolRegistry.sol";
import "src/test/utils/EigenLayerUnitTestSetup.sol";

contract ProtocolRegistryUnitTests is EigenLayerUnitTestSetup, IProtocolRegistryEvents, IProtocolRegistryErrors {
    ProtocolRegistry protocolRegistry;
    ProxyAdminMock proxyAdminMock;

    address defaultOwner;
    address nonOwner;

    function setUp() public virtual override {
        EigenLayerUnitTestSetup.setUp();

        defaultOwner = address(this);
        nonOwner = cheats.randomAddress();

        proxyAdminMock = new ProxyAdminMock();
        protocolRegistry = _deployProtocolRegistry(address(proxyAdminMock));
    }

    function _deployProtocolRegistry(address proxyAdmin) internal returns (ProtocolRegistry registry) {
        registry = ProtocolRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(new ProtocolRegistry(IProxyAdmin(proxyAdmin))),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(ProtocolRegistry.initialize.selector, defaultOwner)
                )
            )
        );
        isExcludedFuzzAddress[address(registry)] = true;
    }

    /// -----------------------------------------------------------------------
    /// initialize()
    /// -----------------------------------------------------------------------

    function test_initialize_Correctness() public {
        assertEq(protocolRegistry.owner(), defaultOwner);
        assertEq(address(protocolRegistry.PROXY_ADMIN()), address(proxyAdminMock));
        cheats.expectRevert("Initializable: contract is already initialized");
        protocolRegistry.initialize(defaultOwner);
    }

    /// -----------------------------------------------------------------------
    /// ship()
    /// -----------------------------------------------------------------------

    function test_ship_OnlyOwner() public {
        address[] memory addresses = new address[](1);
        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        string[] memory names = new string[](1);

        cheats.prank(nonOwner);
        cheats.expectRevert("Ownable: caller is not the owner");
        protocolRegistry.ship(addresses, configs, names, "1.0.0");
    }

    function test_ship_SingleDeployment() public {
        address addr = cheats.randomAddress();
        address[] memory addresses = new address[](1);
        addresses[0] = addr;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});

        string[] memory names = new string[](1);
        names[0] = "TestContract";

        cheats.expectEmit(true, true, true, true, address(protocolRegistry));
        emit DeploymentShipped(addr, configs[0], "1.0.0");

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        assertEq(protocolRegistry.totalDeployments(), 1);
        assertEq(protocolRegistry.getAddress("TestContract"), addr);
    }

    function test_ship_MultipleDeployments() public {
        address addr1 = address(0x1);
        address addr2 = address(0x2);
        address addr3 = address(0x3);

        address[] memory addresses = new address[](3);
        addresses[0] = addr1;
        addresses[1] = addr2;
        addresses[2] = addr3;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](3);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});
        configs[1] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: true, deprecated: false});
        configs[2] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: true, deprecated: true});

        string[] memory names = new string[](3);
        names[0] = "Contract1";
        names[1] = "Contract2";
        names[2] = "Contract3";

        protocolRegistry.ship(addresses, configs, names, "2.0.0");

        assertEq(protocolRegistry.totalDeployments(), 3);
        assertEq(protocolRegistry.getAddress("Contract1"), addr1);
        assertEq(protocolRegistry.getAddress("Contract2"), addr2);
        assertEq(protocolRegistry.getAddress("Contract3"), addr3);
    }

    /// -----------------------------------------------------------------------
    /// configure()
    /// -----------------------------------------------------------------------

    function test_configure_OnlyOwner() public {
        address addr = cheats.randomAddress();
        IProtocolRegistryTypes.DeploymentConfig memory config =
            IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});

        cheats.prank(nonOwner);
        cheats.expectRevert("Ownable: caller is not the owner");
        protocolRegistry.configure(addr, config);
    }

    function test_configure_Correctness() public {
        // First ship a deployment
        address addr = address(0x123);
        address[] memory addresses = new address[](1);
        addresses[0] = addr;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: false, deprecated: false});

        string[] memory names = new string[](1);
        names[0] = "TestContract";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        // Update config
        IProtocolRegistryTypes.DeploymentConfig memory newConfig =
            IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: true, deprecated: true});

        cheats.expectEmit(true, true, true, true, address(protocolRegistry));
        emit DeploymentConfigured(addr, newConfig);

        protocolRegistry.configure(addr, newConfig);

        (,, IProtocolRegistryTypes.DeploymentConfig memory retrievedConfig) = protocolRegistry.getDeployment("TestContract");
        assertEq(retrievedConfig.pausable, true);
        assertEq(retrievedConfig.upgradeable, true);
        assertEq(retrievedConfig.deprecated, true);
    }

    /// -----------------------------------------------------------------------
    /// pauseAll()
    /// -----------------------------------------------------------------------

    function test_pauseAll_OnlyOwner() public {
        cheats.prank(nonOwner);
        cheats.expectRevert("Ownable: caller is not the owner");
        protocolRegistry.pauseAll();
    }

    function test_pauseAll_PausableContracts() public {
        PausableMock pausable1 = new PausableMock();
        PausableMock pausable2 = new PausableMock();
        address nonPausable = address(emptyContract);

        address[] memory addresses = new address[](3);
        addresses[0] = address(pausable1);
        addresses[1] = nonPausable;
        addresses[2] = address(pausable2);

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](3);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});
        configs[1] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: false, deprecated: false});
        configs[2] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});

        string[] memory names = new string[](3);
        names[0] = "Pausable1";
        names[1] = "NonPausable";
        names[2] = "Pausable2";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        protocolRegistry.pauseAll();

        assertTrue(pausable1.paused());
        assertTrue(pausable2.paused());
    }

    function test_pauseAll_SkipsDeprecated() public {
        PausableMock pausable = new PausableMock();
        PausableMock deprecated = new PausableMock();

        address[] memory addresses = new address[](2);
        addresses[0] = address(pausable);
        addresses[1] = address(deprecated);

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](2);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});
        configs[1] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: true});

        string[] memory names = new string[](2);
        names[0] = "Active";
        names[1] = "Deprecated";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        protocolRegistry.pauseAll();

        assertTrue(pausable.paused());
        assertFalse(deprecated.paused());
    }

    /// -----------------------------------------------------------------------
    /// getAddress()
    /// -----------------------------------------------------------------------

    function test_getAddress_ExistingDeployment() public {
        address addr = address(0x456);
        address[] memory addresses = new address[](1);
        addresses[0] = addr;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: false, deprecated: false});

        string[] memory names = new string[](1);
        names[0] = "MyContract";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        assertEq(protocolRegistry.getAddress("MyContract"), addr);
    }

    /// -----------------------------------------------------------------------
    /// getDeployment()
    /// -----------------------------------------------------------------------

    function test_getDeployment_NonUpgradeable() public {
        address addr = address(0x789);
        address[] memory addresses = new address[](1);
        addresses[0] = addr;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});

        string[] memory names = new string[](1);
        names[0] = "NonUpgradeable";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        (address retAddr, address implementation, IProtocolRegistryTypes.DeploymentConfig memory config) =
            protocolRegistry.getDeployment("NonUpgradeable");

        assertEq(retAddr, addr);
        assertEq(implementation, addr); // Non-upgradeable returns same address
        assertEq(config.pausable, true);
        assertEq(config.upgradeable, false);
        assertEq(config.deprecated, false);
    }

    function test_getDeployment_Upgradeable() public {
        address proxyAddr = address(emptyContract);
        address implAddr = address(0xABC);

        proxyAdminMock.setImplementation(proxyAddr, implAddr);

        address[] memory addresses = new address[](1);
        addresses[0] = proxyAddr;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](1);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: true, deprecated: false});

        string[] memory names = new string[](1);
        names[0] = "Upgradeable";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        (address retAddr, address implementation, IProtocolRegistryTypes.DeploymentConfig memory config) =
            protocolRegistry.getDeployment("Upgradeable");

        assertEq(retAddr, proxyAddr);
        assertEq(implementation, implAddr); // Upgradeable returns implementation
        assertEq(config.pausable, false);
        assertEq(config.upgradeable, true);
        assertEq(config.deprecated, false);
    }

    /// -----------------------------------------------------------------------
    /// getAllDeployments()
    /// -----------------------------------------------------------------------

    function test_getAllDeployments_Empty() public {
        (string[] memory names, address[] memory addresses, address[] memory implementations, IProtocolRegistryTypes.DeploymentConfig[] memory configs) =
            protocolRegistry.getAllDeployments();

        assertEq(names.length, 0);
        assertEq(addresses.length, 0);
        assertEq(implementations.length, 0);
        assertEq(configs.length, 0);
    }

    function test_getAllDeployments_Multiple() public {
        address addr1 = address(0x1111);
        address addr2 = address(0x2222);
        address impl2 = address(0x2223);

        proxyAdminMock.setImplementation(addr2, impl2);

        address[] memory addresses = new address[](2);
        addresses[0] = addr1;
        addresses[1] = addr2;

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](2);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: true, upgradeable: false, deprecated: false});
        configs[1] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: true, deprecated: true});

        string[] memory names = new string[](2);
        names[0] = "First";
        names[1] = "Second";

        protocolRegistry.ship(addresses, configs, names, "3.0.0");

        (
            string[] memory retNames,
            address[] memory retAddresses,
            address[] memory retImplementations,
            IProtocolRegistryTypes.DeploymentConfig[] memory retConfigs
        ) = protocolRegistry.getAllDeployments();

        assertEq(retNames.length, 2);
        assertEq(retAddresses.length, 2);
        assertEq(retImplementations.length, 2);
        assertEq(retConfigs.length, 2);

        assertEq(retNames[0], "First");
        assertEq(retNames[1], "Second");
        assertEq(retAddresses[0], addr1);
        assertEq(retAddresses[1], addr2);
        assertEq(retImplementations[0], addr1); // Non-upgradeable
        assertEq(retImplementations[1], impl2); // Upgradeable
        assertEq(retConfigs[0].pausable, true);
        assertEq(retConfigs[1].upgradeable, true);
    }

    /// -----------------------------------------------------------------------
    /// totalDeployments()
    /// -----------------------------------------------------------------------

    function test_totalDeployments_InitiallyZero() public {
        assertEq(protocolRegistry.totalDeployments(), 0);
    }

    function test_totalDeployments_IncreasesWithShip() public {
        address[] memory addresses = new address[](2);
        addresses[0] = address(0x1);
        addresses[1] = address(0x2);

        IProtocolRegistryTypes.DeploymentConfig[] memory configs = new IProtocolRegistryTypes.DeploymentConfig[](2);
        configs[0] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: false, deprecated: false});
        configs[1] = IProtocolRegistryTypes.DeploymentConfig({pausable: false, upgradeable: false, deprecated: false});

        string[] memory names = new string[](2);
        names[0] = "A";
        names[1] = "B";

        protocolRegistry.ship(addresses, configs, names, "1.0.0");

        assertEq(protocolRegistry.totalDeployments(), 2);
    }
}

// Mock contracts for testing
contract PausableMock {
    bool private _paused;

    function pauseAll() external {
        _paused = true;
    }

    function paused() external view returns (bool) {
        return _paused;
    }
}

contract ProxyAdminMock {
    mapping(address => address) private _implementations;

    function setImplementation(address proxy, address implementation) external {
        _implementations[proxy] = implementation;
    }

    function getProxyImplementation(address proxy) external view returns (address) {
        return _implementations[proxy];
    }
}
