// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

// OpenZeppelin Contracts
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Core Contracts
import "src/contracts/core/AllocationManager.sol";
import "src/contracts/core/DelegationManager.sol";
import "src/contracts/core/StrategyManager.sol";
import "src/contracts/permissions/PauserRegistry.sol";
import "src/contracts/permissions/PermissionController.sol";

// Multichain Contracts
import "src/contracts/multichain/CrossChainRegistry.sol";
import "src/contracts/permissions/KeyRegistrar.sol";
import "src/test/mocks/EmptyContract.sol";
import "src/test/mocks/MockAVSRegistrar.sol";

// Test Utils
import "src/test/utils/OperatorWalletLib.sol";

// Forge
import "forge-std/Script.sol";
import "forge-std/Test.sol";

// forge script script/deploy/devnet/multichain/deploy_ecdsa_operatorSet.s.sol --rpc-url $RPC_SEPOLIA --private-key $PRIVATE_KEY --broadcast --sig "run()" --verify $ETHERSCAN_API_KEY
contract DeployOperatorSetECDSA is Script, Test {
    using OperatorWalletLib for *;
    using Strings for uint256;

    Vm cheats = Vm(VM_ADDRESS);

    // Admin that can perform actions on behalf of the operatorSet
    address superAdmin = 0x55b493AACFda9797511B5beA0b52fc2BFa599D0E;
    uint32 operatorSetId = 1;  // Changed from 0 to 1 for ECDSA operator set

    // Contracts
    AllocationManager public allocationManager = AllocationManager(0x42583067658071247ec8CE0A516A58f682002d07);
    DelegationManager public delegationManager = DelegationManager(0xD4A7E1Bd8015057293f0D0A557088c286942e84b);
    StrategyManager public strategyManager = StrategyManager(0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D);
    PermissionController public permissionController = PermissionController(0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37);
    IStrategy public strategy = IStrategy(0x424246eF71b01ee33aA33aC590fd9a0855F5eFbc); // WETH strategy
    IERC20 public weth = IERC20(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
    CrossChainRegistry public crossChainRegistry = CrossChainRegistry(0x287381B1570d9048c4B4C7EC94d21dDb8Aa1352a);
    KeyRegistrar public keyRegistrar = KeyRegistrar(0xA4dB30D08d8bbcA00D40600bee9F029984dB162a);

    // Storage for created operators (only using vmWallet)
    Wallet[] public operators;

    function run() public {
        // Deploy the AVS
        _deployAVS();

        // Create operators
        _createOperators();

        // Deposit for operators
        _depositOperators();

        // Register Keys and Create Reservations
        _configureKeysAndCCR();

        // Write deployment data to JSON
        _writeDeploymentOutput();
    }

    function _deployAVS() internal {
        vm.startBroadcast();

        // Create AVS
        allocationManager.updateAVSMetadataURI(superAdmin, "test-ecdsa");

        // Create operatorSet
        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManagerTypes.CreateSetParams[](1);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        params[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: strategies});

        allocationManager.createOperatorSets(superAdmin, params);

        // Set AVS Registrar - not done because we do it for the BN254 operatorSet for the same AVS
        // Deploy AVS Registrar
        // MockAVSRegistrar avsRegistrar = new MockAVSRegistrar();
        // allocationManager.setAVSRegistrar(superAdmin, IAVSRegistrar(address(avsRegistrar)));

        vm.stopBroadcast();

        // return address(avsRegistrar);
    }

    function _createOperators() internal {
        vm.startBroadcast();

        // Create 2 operators with ECDSA wallets only
        for (uint256 i = 0; i < 3; i++) {
            // Create wallet using unique name
            Wallet memory wallet =
                OperatorWalletLib.createWallet(uint256(keccak256(abi.encodePacked("operatorTestnetECDSA", i.toString()))));
            operators.push(wallet);

            // Label the operator address
            uint256 operatorIndex = i + 4;
            vm.label(wallet.addr, string(abi.encodePacked("ECDSA Operator", operatorIndex.toString())));

            // Send 1 ETH to operator
            payable(wallet.addr).transfer(10 ether);
        }

        vm.stopBroadcast();

        // Register each operator
        for (uint256 i = 0; i < operators.length; i++) {
            vm.startBroadcast(operators[i].privateKey);

            // Add superAdmin as pending admin for this operator
            permissionController.addPendingAdmin(operators[i].addr, superAdmin);

            // Register as operator with delegationManager
            uint256 operatorIndex = i + 4;
            delegationManager.registerAsOperator(
                operators[i].addr,
                0, // earningsReceiver set to operator address
                string(abi.encodePacked("ECDSA Operator", operatorIndex.toString()))
            );

            vm.stopBroadcast();
        }

        // Accept admin role for each operator
        vm.startBroadcast();
        for (uint256 i = 0; i < operators.length; i++) {
            // Accept the admin role
            permissionController.acceptAdmin(operators[i].addr);
        }
        vm.stopBroadcast();
    }

    function _depositOperators() internal {
        for (uint256 i = 0; i < operators.length; i++) {
            vm.startBroadcast(operators[i].privateKey);

            uint256 amount = (i + 4) * 1 ether;

            // Convert 0.5 ETH to WETH
            (bool success,) = address(weth).call{value: amount}(abi.encodeWithSignature("deposit()"));
            require(success, "WETH deposit failed");

            // Approve strategyManager to spend WETH
            weth.approve(address(strategyManager), amount);

            // Deposit WETH into strategy
            strategyManager.depositIntoStrategy(strategy, weth, amount);

            vm.stopBroadcast();
        }
    }

    function _configureKeysAndCCR() internal {
        // Create operator set struct
        OperatorSet memory operatorSet = OperatorSet({avs: superAdmin, id: operatorSetId});

        // Step 1: Configure key material - superAdmin configures operator set to use ECDSA
        vm.startBroadcast();
        keyRegistrar.configureOperatorSet(operatorSet, IKeyRegistrarTypes.CurveType.ECDSA);
        vm.stopBroadcast();

        // Step 2: Register operator keys
        vm.startBroadcast();
        for (uint256 i = 0; i < operators.length; i++) {
            // For ECDSA, the pubkey is just the operator's address packed into bytes
            bytes memory pubkey = abi.encodePacked(operators[i].addr);

            // Generate ECDSA signature
            bytes memory signature =
                _generateECDSASignature(operators[i].addr, operatorSet, operators[i].addr, operators[i].privateKey);

            // Register the key
            keyRegistrar.registerKey(operators[i].addr, operatorSet, pubkey, signature);
        }
        vm.stopBroadcast();

        // // Step 3: Create generation reservation for cross chain registry
        // vm.startBroadcast();

        // // Create operator set config
        // ICrossChainRegistryTypes.OperatorSetConfig memory config =
        //     ICrossChainRegistryTypes.OperatorSetConfig({owner: superAdmin, maxStalenessPeriod: 1 days});

        // // Create chain IDs array with chainID 17000
        // uint256[] memory chainIDs = new uint256[](1);
        // chainIDs[0] = 84_532;

        // // Create generation reservation
        // crossChainRegistry.createGenerationReservation(operatorSet, tableCalculator, config, chainIDs);

        // vm.stopBroadcast();
    }

    function _generateECDSASignature(
        address operator,
        OperatorSet memory operatorSet,
        address keyAddress,
        uint256 privKey
    ) internal view returns (bytes memory) {
        // Get the typehash from KeyRegistrar
        bytes32 ECDSA_KEY_REGISTRATION_TYPEHASH = keyRegistrar.ECDSA_KEY_REGISTRATION_TYPEHASH();

        // Create the struct hash
        bytes32 structHash = keccak256(
            abi.encode(ECDSA_KEY_REGISTRATION_TYPEHASH, operator, operatorSet.avs, operatorSet.id, keyAddress)
        );

        // Create the domain separator message
        bytes32 domainSeparator = keyRegistrar.domainSeparator();
        bytes32 messageHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function _writeOperatorData(Wallet memory operator, uint256 operatorIndex) internal {
        string memory operator_object = "operator";

        // Serialize wallet info
        string memory wallet_object = "wallet";
        vm.serializeUint(wallet_object, "privateKey", operator.privateKey);
        string memory walletOutput = vm.serializeAddress(wallet_object, "address", operator.addr);

        // For ECDSA operators, we only have the wallet (no BLS keys)
        string memory operatorOutput = vm.serializeString(operator_object, "wallet", walletOutput);

        // Write to separate file
        string memory walletOutputPath = string.concat(
            "script/output/devnet/multichain/ecdsa_operator_", 
            (operatorIndex + 4).toString(), 
            ".wallet.json"
        );
        vm.writeJson(operatorOutput, walletOutputPath);
    }

    function _writeDeploymentOutput() internal {
        string memory parent_object = "parent object";

        // Serialize superAdmin
        vm.serializeAddress(parent_object, "superAdmin", superAdmin);

        // Serialize operatorSetId
        vm.serializeUint(parent_object, "operatorSetId", uint256(operatorSetId));

        // Write each operator to a separate file
        for (uint256 i = 0; i < operators.length; i++) {
            _writeOperatorData(operators[i], i);
        }

        // Serialize operators summary for main deployment file
        string memory operators_array = "operators";
        for (uint256 i = 0; i < operators.length; i++) {
            string memory operator_object = string(abi.encodePacked("operator", i.toString()));
            vm.serializeAddress(operator_object, "address", operators[i].addr);
            string memory operatorOutput = vm.serializeString(
                operator_object, 
                "walletFile", 
                string.concat("ecdsa_operator_", (i + 4).toString(), ".wallet.json")
            );
            vm.serializeString(operators_array, string(abi.encodePacked("[", i.toString(), "]")), operatorOutput);
        }

        // Serialize contract addresses
        string memory contracts_object = "contracts";
        vm.serializeAddress(contracts_object, "allocationManager", address(allocationManager));
        vm.serializeAddress(contracts_object, "delegationManager", address(delegationManager));
        vm.serializeAddress(contracts_object, "strategyManager", address(strategyManager));
        vm.serializeAddress(contracts_object, "strategy", address(strategy));
        string memory contractsOutput = vm.serializeAddress(contracts_object, "keyRegistrar", address(keyRegistrar));

        // Combine all outputs
        vm.serializeString(
            parent_object, "operators", vm.serializeString(operators_array, "length", operators.length.toString())
        );
        vm.serializeString(parent_object, "contracts", contractsOutput);
        string memory finalJson = vm.serializeAddress(parent_object, "avs", superAdmin);

        // Write to file
        vm.writeJson(finalJson, "script/output/devnet/multichain/avs_deployment_ecdsa.json");
    }
} 