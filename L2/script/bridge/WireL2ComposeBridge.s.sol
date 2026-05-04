// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { L2ComposeBridge } from "@ssv/src/bridge/L2ComposeBridge.sol";

/// @title WireL2ComposeBridge (L2 side)
/// Env:
///   OWNER              owner of the L2ComposeBridge (was msg.sender at deploy)
///   L2_COMPOSE_BRIDGE  L2ComposeBridge address on this L2
///   L1_COMPOSE_BRIDGE  ComposeL1Bridge proxy address on the paired L1
contract WireL2ComposeBridge is Script {
    function run() external {
        address owner    = vm.envAddress("OWNER");
        address l2Bridge = vm.envAddress("L2_COMPOSE_BRIDGE");
        address l1Bridge = vm.envAddress("L1_COMPOSE_BRIDGE");

        address current = L2ComposeBridge(payable(l2Bridge)).otherBridge();
        if (current == l1Bridge) {
            console.log("\n[1] L2Bridge.otherBridge already set: skip");
            return;
        }
        if (current != address(0)) revert("L2Bridge.otherBridge mismatch");

        vm.startBroadcast(owner);
        L2ComposeBridge(payable(l2Bridge)).setOtherBridge(l1Bridge);
        vm.stopBroadcast();

        console.log("\n[1] L2Bridge.setOtherBridge         :", l1Bridge);
        console.log("\n========================================");
        console.log("Done (L2 wiring)");
        console.log("========================================");
    }
}
