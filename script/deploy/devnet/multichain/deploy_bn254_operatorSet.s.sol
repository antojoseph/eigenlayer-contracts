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

// Libraries
import "src/contracts/libraries/BN254.sol";

// Test Utils
import "src/test/utils/OperatorWalletLib.sol";

// Forge
import "forge-std/Script.sol";
import "forge-std/Test.sol";

// forge script script/deploy/devnet/multichain/deploy_bn254_operatorSet.s.sol --rpc-url $RPC_SEPOLIA --private-key $PRIVATE_KEY --broadcast --sig "run()" --verify $ETHERSCAN_API_KEY --ffi
contract DeployOperatorSet is Script, Test {
    using OperatorWalletLib for *;
    using Strings for uint256;
    using BN254 for BN254.G1Point;

    Vm cheats = Vm(VM_ADDRESS);

    // Admin that can perform actions on behalf of the operatorSet
    address superAdmin = 0x55b493AACFda9797511B5beA0b52fc2BFa599D0E;
    uint32 operatorSetId = 0;

    // Contracts
    AllocationManager public allocationManager = AllocationManager(0x42583067658071247ec8CE0A516A58f682002d07);
    DelegationManager public delegationManager = DelegationManager(0xD4A7E1Bd8015057293f0D0A557088c286942e84b);
    StrategyManager public strategyManager = StrategyManager(0x2E3D6c0744b10eb0A4e6F679F71554a39Ec47a5D);
    PermissionController public permissionController = PermissionController(0x44632dfBdCb6D3E21EF613B0ca8A6A0c618F5a37);
    IStrategy public strategy = IStrategy(0x424246eF71b01ee33aA33aC590fd9a0855F5eFbc); // WETH strategy
    IERC20 public weth = IERC20(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
    CrossChainRegistry public crossChainRegistry = CrossChainRegistry(0x287381B1570d9048c4B4C7EC94d21dDb8Aa1352a);
    KeyRegistrar public keyRegistrar = KeyRegistrar(0xA4dB30D08d8bbcA00D40600bee9F029984dB162a);

    // Storage for created operators
    Operator[] public operators;

    function run() public {
        // Deploy the AVS
        // _deployAVS();

        // Create operators
        _createOperators();

        // Deposit for operators
        // _depositOperators();

        // Register Keys and Create Reservations
        _configureKeysAndCCR();

        // Write deployment data to JSON
        _writeDeploymentOutput();
    }

    function _deployAVS() internal returns (address) {
        vm.startBroadcast();

        // Create AVS
        allocationManager.updateAVSMetadataURI(superAdmin, "test");

        // Create operatorSet
        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManagerTypes.CreateSetParams[](1);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        params[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: operatorSetId, strategies: strategies});

        allocationManager.createOperatorSets(superAdmin, params);

        // Set AVS Registrar
        // Deploy AVS Registrar
        MockAVSRegistrar avsRegistrar = new MockAVSRegistrar();
        allocationManager.setAVSRegistrar(superAdmin, IAVSRegistrar(address(avsRegistrar)));

        vm.stopBroadcast();

        return address(avsRegistrar);
    }

    function _createOperators() internal {
        // vm.startBroadcast();

        // Create 3 operators with BLS wallets
        for (uint256 i = 0; i < 3; i++) {
            // Create operator with BLS wallet using unique name
            Operator memory operator =
                OperatorWalletLib.createOperator(string(abi.encodePacked("operatorTestnetBN254", i.toString())));
            operators.push(operator);

            console.log("operator", operator.key.addr);

            // // Send 10 ETH to operator
            // payable(operator.key.addr).transfer(10 ether);
        }

        // vm.stopBroadcast();

        // // Register each operator
        // for (uint256 i = 0; i < operators.length; i++) {
        //     vm.startBroadcast(operators[i].key.privateKey);

        //     // Add superAdmin as pending admin for this operator
        //     permissionController.addPendingAdmin(operators[i].key.addr, superAdmin);

        //     // Register as operator with delegationManager
        //     delegationManager.registerAsOperator(
        //         operators[i].key.addr,
        //         0, // earningsReceiver set to operator address
        //         string(abi.encodePacked("Operator", i.toString()))
        //     );

        //     vm.stopBroadcast();
        // }

        // // Accept admin role for each operator
        // vm.startBroadcast();
        // for (uint256 i = 0; i < operators.length; i++) {
        //     // Accept the admin role
        //     permissionController.acceptAdmin(operators[i].key.addr);
        // }
        // vm.stopBroadcast();
    }

    function _depositOperators() internal {
        for (uint256 i = 0; i < operators.length; i++) {
            vm.startBroadcast(operators[i].key.privateKey);

            // Convert i ETH to WETH
            uint256 amount = (i + 1) * 1 ether;
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

        // Step 1: Configure key material - superAdmin configures operator set to use BN254
        vm.startBroadcast();
        keyRegistrar.configureOperatorSet(operatorSet, IKeyRegistrarTypes.CurveType.BN254);
        vm.stopBroadcast();

        // Step 2: Register operator keys
        vm.startBroadcast();
        for (uint256 i = 0; i < operators.length; i++) {
            // Encode the BN254 key (G1 and G2 points)
            bytes memory pubkey = abi.encode(
                operators[i].signingKey.publicKeyG1.X,
                operators[i].signingKey.publicKeyG1.Y,
                operators[i].signingKey.publicKeyG2.X,
                operators[i].signingKey.publicKeyG2.Y
            );

            // Generate BN254 signature
            bytes memory signature =
                _generateBN254Signature(operators[i].key.addr, operatorSet, pubkey, operators[i].signingKey.privateKey);

            // Register the key
            keyRegistrar.registerKey(operators[i].key.addr, operatorSet, pubkey, signature);
        }
        vm.stopBroadcast();

        // Step 3: Create generation reservation for cross chain registry
        // vm.startBroadcast();

        // // Create operator set config
        // ICrossChainRegistryTypes.OperatorSetConfig memory config =
        //     ICrossChainRegistryTypes.OperatorSetConfig({owner: superAdmin, maxStalenessPeriod: 1 days});

        // // Create chain IDs array with chainID 17000
        // uint256[] memory chainIDs = new uint256[](1);
        // chainIDs[0] = 17_000;

        // // Create generation reservation
        // crossChainRegistry.createGenerationReservation(operatorSet, tableCalculator, config, chainIDs);

        // vm.stopBroadcast();
    }

    function _generateBN254Signature(
        address operator,
        OperatorSet memory operatorSet,
        bytes memory pubkey,
        uint256 privKey
    ) internal view returns (bytes memory) {
        // Get the typehash from KeyRegistrar
        bytes32 BN254_KEY_REGISTRATION_TYPEHASH = keyRegistrar.BN254_KEY_REGISTRATION_TYPEHASH();

        // Create the struct hash
        bytes32 structHash = keccak256(
            abi.encode(BN254_KEY_REGISTRATION_TYPEHASH, operator, operatorSet.avs, operatorSet.id, keccak256(pubkey))
        );

        // Create the domain separator message
        bytes32 messageHash = keyRegistrar.domainSeparator();
        messageHash = keccak256(abi.encodePacked("\x19\x01", messageHash, structHash));

        // Hash the message to a G1 point and sign with private key
        BN254.G1Point memory msgPoint = BN254.hashToG1(messageHash);
        BN254.G1Point memory signature = msgPoint.scalar_mul(privKey);

        return abi.encode(signature.X, signature.Y);
    }

    function _writeOperatorData(Operator memory operator, uint256 operatorIndex) internal {
        string memory operator_object = "operator";

        // Serialize regular wallet info
        string memory wallet_object = "wallet";
        vm.serializeUint(wallet_object, "privateKey", operator.key.privateKey);
        string memory walletOutput = vm.serializeAddress(wallet_object, "address", operator.key.addr);

        // Serialize BLS wallet info
        string memory blsWallet_object = "blsWallet";
        vm.serializeUint(blsWallet_object, "privateKey", operator.signingKey.privateKey);

        // Serialize publicKeyG1
        string memory publicKeyG1_object = "publicKeyG1";
        vm.serializeUint(publicKeyG1_object, "x", operator.signingKey.publicKeyG1.X);
        string memory publicKeyG1Output = vm.serializeUint(publicKeyG1_object, "y", operator.signingKey.publicKeyG1.Y);
        vm.serializeString(blsWallet_object, "publicKeyG1", publicKeyG1Output);

        // Serialize publicKeyG2
        string memory publicKeyG2_object = "publicKeyG2";
        vm.serializeUint(publicKeyG2_object, "x0", operator.signingKey.publicKeyG2.X[0]);
        vm.serializeUint(publicKeyG2_object, "x1", operator.signingKey.publicKeyG2.X[1]);
        vm.serializeUint(publicKeyG2_object, "y0", operator.signingKey.publicKeyG2.Y[0]);
        string memory publicKeyG2Output =
            vm.serializeUint(publicKeyG2_object, "y1", operator.signingKey.publicKeyG2.Y[1]);
        string memory blsWalletOutput = vm.serializeString(blsWallet_object, "publicKeyG2", publicKeyG2Output);

        // Combine wallet and blsWallet into operator object
        vm.serializeString(operator_object, "wallet", walletOutput);
        string memory operatorOutput = vm.serializeString(operator_object, "blsWallet", blsWalletOutput);

        // Write to separate file
        string memory walletOutputPath = string.concat(
            "script/output/devnet/multichain/operator_", 
            (operatorIndex + 1).toString(), 
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
            vm.serializeAddress(operator_object, "address", operators[i].key.addr);
            string memory operatorOutput = vm.serializeString(
                operator_object, 
                "walletFile", 
                string.concat("operator_", (i + 1).toString(), ".wallet.json")
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
        vm.writeJson(finalJson, "script/output/devnet/multichain/avs_bn254_deployment.json");
    }
}