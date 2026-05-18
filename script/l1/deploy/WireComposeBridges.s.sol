// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { ComposeL1Bridge } from "src/l1/ComposeL1Bridge.sol";
import { ComposeETHLockbox } from "src/l1/ComposeETHLockbox.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ComposeConfig } from "script/l1/libraries/ComposeConfig.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

/// @title WireComposeBridges (L1 side)
/// Config (config.json via ROLLUP_NAME):
///   l1.proxyAdminOwner                  owner that can call setOtherBridge / authorizePortal
///   rollups.<name>.l1.composeBridge     ComposeL1Bridge proxy address on this L1
///   rollups.<name>.l2ComposeBridge      L2ComposeBridge address on the paired L2
///   rollups.<name>.l1.portalProxy       ComposePortal proxy address on this L1
///   l1.deployed.ethLockbox              ComposeETHLockbox proxy address (shared across rollups)
contract WireComposeBridges is Script {
    function run() external {
        address owner       = ComposeConfig.proxyAdminOwner();
        address l1Bridge    = RollupConfig.l1ComposeBridge();
        address l2Bridge    = RollupConfig.l2ComposeBridge();
        address portal      = RollupConfig.portalProxy();
        address ethLockbox  = ComposeConfig.ethLockbox();

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
