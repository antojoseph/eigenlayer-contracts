
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../releases/Env.sol";
import {ProposeMinter} from "./1-proposeMinter.s.sol";

/**
 * Purpose: Propose the minter on a TESTNET environment
 */
contract ExecuteMinter is ProposeMinter {
    using Env for *;

    function _runAsMultisig() internal virtual override prank(Env.protocolCouncilMultisig()) {
        bytes memory calldata_to_executor = _getCalldataToExecutor();

        TimelockController timelock = Env.timelockController();
        timelock.execute({
            target: Env.executorMultisig(),
            value: 0,
            payload: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });
    }

    function testScript() public virtual override {
        TimelockController timelock = Env.timelockController();
        bytes memory calldata_to_executor = _getCalldataToExecutor();
        bytes32 txHash = timelock.hashOperation({
            target: Env.executorMultisig(),
            value: 0,
            data: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });

        // // 1- run queueing logic
        // ProposeMinter._runAsMultisig();
        // _unsafeResetHasPranked(); // reset hasPranked so we can use it again

        // assertTrue(timelock.isOperationPending(txHash), "Transaction should be queued.");
        // assertFalse(timelock.isOperationReady(txHash), "Transaction should NOT be ready for execution.");
        // assertFalse(timelock.isOperationDone(txHash), "Transaction should NOT be complete.");

        // 2- warp past delay
        vm.warp(block.timestamp + timelock.getMinDelay()); // 1 tick after ETA
        assertEq(timelock.isOperationReady(txHash), true, "Transaction should be executable.");

        // 3- execute
        execute();

        assertTrue(timelock.isOperationDone(txHash), "Transaction should be complete.");
        assertTrue(
            IMinter(address(Env.proxy.beigen())).isMinter(MINTER), "Minter should be set"
        );
    }
}

interface IMinter {
    function isMinter(address minter) external view returns (bool);
}
