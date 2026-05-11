// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";
import {L2ComposeBridge} from "src/l2/bridge/L2ComposeBridge.sol";

/// @title WireL2ComposeBridge
/// @notice Wire L2ComposeBridge to its L1 counterpart after both sides are deployed.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   owner              owner of the L2ComposeBridge
///
/// Env:
///   ROLLUP_NAME        selects section in rollups.toml
///   DEPLOYER_KEY       private key for broadcast
///   L2_COMPOSE_BRIDGE  L2ComposeBridge address on this L2
///   L1_COMPOSE_BRIDGE  ComposeL1Bridge proxy address on the paired L1
contract WireL2ComposeBridge is Script {
    function run() external {
        address l2Bridge = vm.envAddress("L2_COMPOSE_BRIDGE");
        address l1Bridge = vm.envAddress("L1_COMPOSE_BRIDGE");

        address current = L2ComposeBridge(payable(l2Bridge)).otherBridge();
        if (current == l1Bridge) {
            console.log("\n[1] L2Bridge.otherBridge already set: skip");
            return;
        }
        if (current != address(0)) revert("L2Bridge.otherBridge mismatch");

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));
        L2ComposeBridge(payable(l2Bridge)).setOtherBridge(l1Bridge);
        vm.stopBroadcast();

        console.log("\n[1] L2Bridge.setOtherBridge         :", l1Bridge);
        console.log("\n========================================");
        console.log("Done (L2 wiring)");
        console.log("========================================");
    }
}
