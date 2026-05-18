// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ComposePortal } from "src/l1/ComposePortal.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

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
        portalProxy = RollupConfig.portalProxy();
        proxyAdmin = RollupConfig.l1ProxyAdmin();
        proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();
        proofMaturityDelaySeconds = _proofMaturityDelaySeconds;

        console.log("portalProxy          :", portalProxy);
        console.log("proxyAdmin           :", proxyAdmin);
        console.log("proxyAdminOwner      :", proxyAdminOwner);
        console.log("proofMaturityDelay   :", proofMaturityDelaySeconds);
    }

    function _deployImpl() internal {
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        newImpl = address(new ComposePortal(proofMaturityDelaySeconds));
        vm.stopBroadcast();
        console.log("newImpl              :", newImpl);
    }

    function _upgradePortal() internal {
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        IProxyAdmin(proxyAdmin).upgrade(payable(portalProxy), newImpl);
        vm.stopBroadcast();
        console.log("upgraded             :", portalProxy, "->", newImpl);
    }
}
