// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {ComposePortal} from "src/l1/ComposePortal.sol";
import {ComposeConfig} from "script/l1/libraries/ComposeConfig.sol";
import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";

/// @notice Deploys a new ComposePortal implementation and upgrades the existing proxy.
///         New impl calls markTokenAsL2Wrapped on deposit for whitelist tracking.
///
/// Env:
///   ROLLUP_NAME          selects rollup in config.json
///   ROLLUP_OWNER_KEY     private key of rollups.<name>.l1.proxyAdminOwner
contract UpgradeComposePortalImpl is Script {
    function run() external {
        address proxyAdmin = RollupConfig.l1ProxyAdmin();
        address portalProxy = RollupConfig.portalProxy();
        address proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();
        address depositWhitelist = ComposeConfig.depositWhitelist();

        console.log("========================================");
        console.log("Upgrade ComposePortal impl");
        console.log("  rollup       :", RollupConfig.rollupName());
        console.log("  proxyAdmin   :", proxyAdmin);
        console.log("  portalProxy  :", portalProxy);
        console.log("  whitelist    :", depositWhitelist);
        console.log("  owner        :", proxyAdminOwner);
        console.log("========================================");

        require(depositWhitelist != address(0), "depositWhitelist not configured");

        vm.startBroadcast(vm.envUint("ROLLUP_OWNER_KEY"));

        address newImpl = address(new ComposePortal(0));
        IProxyAdmin(proxyAdmin).upgrade(payable(portalProxy), newImpl);

        console.log("new impl     :", newImpl);
        console.log("proxy upgraded");

        vm.stopBroadcast();

        require(
            keccak256(bytes(ComposePortal(payable(portalProxy)).version())) == keccak256(bytes("1.1.0-compose")),
            "portal version mismatch"
        );
    }
}
