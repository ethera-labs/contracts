// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {IComposeAnchorStateRegistry} from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";
import {IDisputeGameFactory} from "interfaces/dispute/IDisputeGameFactory.sol";
import {GameType} from "@optimism/src/dispute/lib/Types.sol";

contract UpdateDisputeGameVkey is Script {
    uint32 public constant COMPOSE_GAME_TYPE = 5555;

    function run() external {
        address dgf = vm.envAddress("DISPUTE_GAME_FACTORY");
        address sp1Verifier = vm.envAddress("SP1_VERIFIER");
        bytes32 vkey = vm.envBytes32("AGGREGATION_VKEY");
        address asr = vm.envAddress("ANCHOR_STATE_REGISTRY");
        address proposer = vm.envAddress("AUTHORIZED_PROPOSER");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        ComposeDisputeGame gameImpl = new ComposeDisputeGame(sp1Verifier, vkey, IComposeAnchorStateRegistry(asr), proposer);
        console.log("new ComposeDisputeGame impl:", address(gameImpl));

        IDisputeGameFactory(dgf).setImplementation(GameType.wrap(COMPOSE_GAME_TYPE), gameImpl);
        console.log("registered in DGF at game type 5555");

        vm.stopBroadcast();
    }
}
