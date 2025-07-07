// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

// Core Contracts
import "src/contracts/core/AllocationManager.sol";
import "src/contracts/interfaces/IAllocationManager.sol";
import "src/contracts/libraries/OperatorSetLib.sol";

// Forge
import "forge-std/Script.sol";
import "forge-std/Test.sol";

// forge script script/deploy/devnet/mutlichain/register_allocate_operators.s.sol --rpc-url $RPC_SEPOLIA --private-key $PRIVATE_KEY --broadcast --sig "run()"
contract RegisterAllocateOperators is Script, Test {
    using stdJson for string;

    // Admin that can perform actions on behalf of the operatorSet
    address superAdmin = 0x8D8A8D3f88f6a6DA2083D865062bFBE3f1cfc293;
    address avs = 0x8D8A8D3f88f6a6DA2083D865062bFBE3f1cfc293;
    uint32 operatorSetId = 1;

    // Contracts
    AllocationManager public allocationManager = AllocationManager(0x42583067658071247ec8CE0A516A58f682002d07);
    IStrategy public strategy = IStrategy(0x424246eF71b01ee33aA33aC590fd9a0855F5eFbc); // WETH strategy

    function run() public {
        // Create operators array
        address[] memory operators = new address[](2);
        operators[0] = 0x8F3bd2b7E3Ae92ce2305a8b28741684E34bAe49E;
        operators[1] = 0xF318c6D757d095Ba6dea320B3fE366c41b460c7b;

        // Create operator set struct
        // OperatorSet memory operatorSet = OperatorSet({avs: avs, id: operatorSetId});

        // Prepare operatorSetIds array
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = operatorSetId;

        // Register each operator to the operator set
        vm.startBroadcast();
        for (uint256 i = 0; i < operators.length; i++) {
            // Register operator to operator set
            IAllocationManagerTypes.RegisterParams memory registerParams =
                IAllocationManagerTypes.RegisterParams({avs: avs, operatorSetIds: operatorSetIds, data: ""});

            allocationManager.registerForOperatorSets(operators[i], registerParams);
        }

        // Allocate each operator to the operator set
        for (uint256 i = 0; i < operators.length; i++) {
            // Get the operator's max magnitude for the strategy
            uint64 maxMagnitude = allocationManager.getMaxMagnitude(operators[i], strategy);

            // Create strategies array
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = strategy;

            // Create magnitudes array (allocate everything)
            uint64[] memory magnitudes = new uint64[](1);
            magnitudes[0] = maxMagnitude;

            // Create allocation params
            IAllocationManagerTypes.AllocateParams[] memory allocateParams =
                new IAllocationManagerTypes.AllocateParams[](1);
            allocateParams[0] = IAllocationManagerTypes.AllocateParams({
                operatorSet: operatorSet,
                strategies: strategies,
                newMagnitudes: magnitudes
            });

            // Modify allocations
            allocationManager.modifyAllocations(operators[i], allocateParams);
        }
        vm.stopBroadcast();

        console.log(
            "Successfully registered and allocated", operators.length, "operators to operator set", operatorSetId
        );
    }
}
