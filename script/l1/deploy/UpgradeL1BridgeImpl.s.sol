// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ComposeL1Bridge } from "src/l1/ComposeL1Bridge.sol";
import { ComposeConfig } from "script/l1/libraries/ComposeConfig.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

/// @notice Deploys a new ComposeL1Bridge implementation and upgrades the existing proxy.
///
/// Env:
///   ROLLUP_NAME          selects rollup in config.json
///   ROLLUP_OWNER_KEY     private key of proxyAdminOwner
contract UpgradeL1BridgeImpl is Script {
    function run() external {
        address proxyAdmin      = RollupConfig.l1ProxyAdmin();
        address bridgeProxy     = RollupConfig.l1ComposeBridge();
        address proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();

        console.log("========================================");
        console.log("Upgrade ComposeL1Bridge impl");
        console.log("  rollup      :", RollupConfig.rollupName());
        console.log("  proxyAdmin  :", proxyAdmin);
        console.log("  bridgeProxy :", bridgeProxy);
        console.log("  owner       :", proxyAdminOwner);
        console.log("========================================");

        vm.startBroadcast(vm.envUint("ROLLUP_OWNER_KEY"));

        address newImpl = address(new ComposeL1Bridge());
        IProxyAdmin(proxyAdmin).upgrade(payable(bridgeProxy), newImpl);

        console.log("new impl     :", newImpl);
        console.log("proxy upgraded");

        vm.stopBroadcast();
    }
}
