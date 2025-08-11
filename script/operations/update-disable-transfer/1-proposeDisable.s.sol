// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../releases/Env.sol";
import {MultisigBuilder} from "zeus-templates/templates/MultisigBuilder.sol";
import {MultisigCall, Encode} from "zeus-templates/utils/Encode.sol";
import {IBackingEigen} from "src/contracts/interfaces/IBackingEigen.sol";

/**
 * Purpose: Propose disabling transfer restrictions on the BackingEigen contract
 */
contract ProposeDisableTransferRestrictions is MultisigBuilder {
    using Env for *;
    using Encode for *;

    function _runAsMultisig() internal virtual override prank(Env.opsMultisig()) {
        bytes memory calldataToExecutor = _getCalldataToExecutor();

        TimelockController timelock = Env.timelockController();
        timelock.schedule({
            target: Env.executorMultisig(),
            value: 0,
            data: calldataToExecutor,
            predecessor: 0,
            salt: 0,
            delay: timelock.getMinDelay()
        });
    }

    function _getCalldataToExecutor() public virtual returns (bytes memory) {
        MultisigCall[] storage executorCalls = Encode.newMultisigCalls().append({
            to: address(Env.proxy.beigen()),
            data: abi.encodeWithSelector(IBackingEigen.disableTransferRestrictions.selector)
        });

        return Encode.gnosisSafe.execTransaction({
            from: address(Env.timelockController()),
            to: Env.multiSendCallOnly(),
            op: Encode.Operation.DelegateCall,
            data: Encode.multiSend(executorCalls)
        });
    }

    function testScript() public virtual {
        TimelockController timelock = Env.timelockController();
        bytes memory calldata_to_executor = _getCalldataToExecutor();
        bytes32 txHash = timelock.hashOperation({
            target: Env.executorMultisig(),
            value: 0,
            data: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });

        // Check that the upgrade does not exist in the timelock
        assertFalse(timelock.isOperationPending(txHash), "Transaction should NOT be queued.");

        execute();

        // Check that the upgrade has been added to the timelock
        assertTrue(timelock.isOperationPending(txHash), "Transaction should be queued.");
    }
}
