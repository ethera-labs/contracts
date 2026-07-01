// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {ComposeAnchorStateRegistry} from "src/l1/ComposeAnchorStateRegistry.sol";

/// @title UpgradeASRImpl
/// @notice Upgrade of an existing ComposeAnchorStateRegistry proxy to a fresh
///         impl with a new DISPUTE_GAME_FINALITY_DELAY_SECONDS value.
///
/// Env:
///   PROXY_ADMIN            existing ComposeProxyAdmin
///   PROXY_ADMIN_OWNER      owner of ProxyAdmin (signs upgrade)
///   ASR_PROXY              existing ComposeAnchorStateRegistry proxy
///   DG_FINALITY_DELAY      new dispute game finality delay in seconds
contract UpgradeASRImpl is Script {
    function run() external returns (address newImplAddr) {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        address asrProxy = vm.envAddress("ASR_PROXY");
        uint256 finalityDelay = vm.envUint("DG_FINALITY_DELAY");

        vm.startBroadcast(proxyAdminOwner);

        ComposeAnchorStateRegistry newImpl = new ComposeAnchorStateRegistry(finalityDelay);
        newImplAddr = address(newImpl);
        console.log("\n[1] new ASR impl :", newImplAddr);

        IProxyAdmin(proxyAdmin).upgrade(payable(asrProxy), newImplAddr);
        console.log("[2] upgrade(asrProxy, newImpl) : ok");

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("  ASR proxy       :", asrProxy);
        console.log("  new ASR impl    :", newImplAddr);
        console.log("========================================");
    }
}
