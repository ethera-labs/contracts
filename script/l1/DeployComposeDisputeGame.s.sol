// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {IComposeAnchorStateRegistry} from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";

contract DeployComposeDisputeGame is Script {
    function run(
        address _proofVerifier,
        bytes32 _aggregationVkey,
        address _asr,
        address _authorizedProposer
    ) public returns (address composeDisputeGame) {
        vm.startBroadcast();

        console.log("Deploying ComposeDisputeGame implementation...");
        composeDisputeGame = address(
            new ComposeDisputeGame(
                _proofVerifier,
                _aggregationVkey,
                IComposeAnchorStateRegistry(_asr),
                _authorizedProposer
            )
        );

        console.log(
            "ComposeDisputeGame implementation deployed at:",
            composeDisputeGame
        );

        vm.stopBroadcast();
    }
}
