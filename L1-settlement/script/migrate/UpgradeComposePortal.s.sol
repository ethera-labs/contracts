// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ComposePortal } from "src/ComposePortal.sol";

contract UpgradeComposePortal is Script {
    address internal portalProxy;
    address internal proxyAdmin;
    address internal proxyAdminOwner;
    uint256 internal proofMaturityDelaySeconds;
    address internal newImpl;

    function run(uint256 _proofMaturityDelaySeconds, bool dryRun) external {
        _loadConfig(_proofMaturityDelaySeconds);
        _deployImpl();

        if (!dryRun) {
            _upgradePortal();
        } else {
            console.log("[DRY RUN] Would upgrade portal proxy to:", newImpl);
        }
    }

    function _loadConfig(uint256 _proofMaturityDelaySeconds) internal {
        portalProxy = vm.envAddress("PORTAL_PROXY");
        proxyAdmin = vm.envAddress("PROXY_ADMIN");
        proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        proofMaturityDelaySeconds = _proofMaturityDelaySeconds;

        console.log("portalProxy          :", portalProxy);
        console.log("proxyAdmin           :", proxyAdmin);
        console.log("proxyAdminOwner      :", proxyAdminOwner);
        console.log("proofMaturityDelay   :", proofMaturityDelaySeconds);
    }

    function _deployImpl() internal {
        vm.startBroadcast(proxyAdminOwner);
        newImpl = address(new ComposePortal(proofMaturityDelaySeconds));
        vm.stopBroadcast();
        console.log("newImpl              :", newImpl);
    }

    function _upgradePortal() internal {
        vm.startBroadcast(proxyAdminOwner);
        IProxyAdmin(proxyAdmin).upgrade(payable(portalProxy), newImpl);
        vm.stopBroadcast();
        console.log("upgraded             :", portalProxy, "->", newImpl);
    }
}
