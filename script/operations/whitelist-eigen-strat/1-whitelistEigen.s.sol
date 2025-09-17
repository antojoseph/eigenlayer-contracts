// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../../releases/Env.sol";
import {MultisigBuilder} from "zeus-templates/templates/MultisigBuilder.sol";
import {MultisigCall, Encode} from "zeus-templates/utils/Encode.sol";
import {IBackingEigen} from "src/contracts/interfaces/IBackingEigen.sol";

/**
 * Purpose: Propose the minter on a TESTNET environment
 */
contract ProposeMinter is MultisigBuilder {
    using Env for *;
    using Encode for *;

    function _runAsMultisig() internal virtual override prank(Env.opsMultisig()) {
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);
        strategiesToWhitelist[0] = IStrategy(address(Env.proxy.eigenStrategy()));
        Env.proxy.strategyFactory().whitelistStrategies(strategiesToWhitelist);
    }

    function testScript() public virtual {
        execute();
    }
}
