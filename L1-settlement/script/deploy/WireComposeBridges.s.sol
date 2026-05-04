// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { ComposeL1Bridge } from "src/ComposeL1Bridge.sol";
import { ComposeETHLockbox } from "src/ComposeETHLockbox.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";

/// @title WireComposeBridges (L1 side)
/// Env:
///   PROXY_ADMIN_OWNER   owner that can call setOtherBridge / authorizePortal
///   L1_COMPOSE_BRIDGE   ComposeL1Bridge proxy address on this L1
///   L2_COMPOSE_BRIDGE   L2ComposeBridge address on the paired L2
///   COMPOSE_PORTAL      ComposePortal proxy address on this L1
///   COMPOSE_ETH_LOCKBOX ComposeETHLockbox proxy address (shared across rollups)
contract WireComposeBridges is Script {
    function run() external {
        address owner       = vm.envAddress("PROXY_ADMIN_OWNER");
        address l1Bridge    = vm.envAddress("L1_COMPOSE_BRIDGE");
        address l2Bridge    = vm.envAddress("L2_COMPOSE_BRIDGE");
        address portal      = vm.envAddress("COMPOSE_PORTAL");
        address ethLockbox  = vm.envAddress("COMPOSE_ETH_LOCKBOX");

        vm.startBroadcast(owner);

        // [1] L1 bridge -> L2 bridge
        address current = ComposeL1Bridge(payable(l1Bridge)).otherBridge();
        if (current == address(0)) {
            ComposeL1Bridge(payable(l1Bridge)).setOtherBridge(l2Bridge);
            console.log("\n[1] L1Bridge.setOtherBridge         :", l2Bridge);
        } else if (current == l2Bridge) {
            console.log("\n[1] L1Bridge.otherBridge already set: skip");
        } else {
            revert("L1Bridge.otherBridge mismatch");
        }

        // [2] ETHLockbox <- ComposePortal
        bool alreadyAuth = ComposeETHLockbox(payable(ethLockbox))
            .authorizedPortals(IOptimismPortal2(payable(portal)));
        if (!alreadyAuth) {
            ComposeETHLockbox(payable(ethLockbox))
                .authorizePortal(IOptimismPortal2(payable(portal)));
            console.log("[2] ETHLockbox.authorizePortal      :", portal);
        } else {
            console.log("[2] ETHLockbox already authorized   : skip");
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done (L1 wiring)");
        console.log("========================================");
    }
}
