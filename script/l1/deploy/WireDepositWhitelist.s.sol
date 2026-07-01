// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {ComposePortal} from "src/l1/ComposePortal.sol";
import {IL1DepositWhitelist} from "src/l1/interfaces/IL1DepositWhitelist.sol";
import {ComposeConfig} from "script/l1/libraries/ComposeConfig.sol";
import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";

/// @notice Wires L1DepositWhitelist to ComposePortal (per rollup).
///         Sets the whitelist reference on the portal so deposits are gated.
///
/// Env:
///   ROLLUP_NAME          selects rollup in config.json
///   ROLLUP_OWNER_KEY     private key of rollups.<name>.l1.proxyAdminOwner
contract WireDepositWhitelist is Script {
    function run() external {
        address portalProxy = RollupConfig.portalProxy();
        address proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();
        address depositWhitelist = ComposeConfig.depositWhitelist();

        console.log("========================================");
        console.log("Wire DepositWhitelist to ComposePortal");
        console.log("  rollup       :", RollupConfig.rollupName());
        console.log("  portalProxy  :", portalProxy);
        console.log("  whitelist    :", depositWhitelist);
        console.log("  owner        :", proxyAdminOwner);
        console.log("========================================");

        require(depositWhitelist != address(0), "depositWhitelist not configured");

        vm.startBroadcast(vm.envUint("ROLLUP_OWNER_KEY"));

        ComposePortal(payable(portalProxy)).setDepositWhitelist(IL1DepositWhitelist(depositWhitelist));

        console.log("Whitelist wired to portal");

        vm.stopBroadcast();

        require(
            address(ComposePortal(payable(portalProxy)).depositWhitelist()) == depositWhitelist,
            "whitelist reference not set correctly"
        );
        console.log("Verified: portal.depositWhitelist == whitelist");
    }
}
