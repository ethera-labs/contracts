// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { IProxy } from "interfaces/universal/IProxy.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

/// @title UpgradeToPortalInterop
/// @notice Upgrades a standard OptimismPortal2 (v5.x) to OptimismPortalInterop.
///         Required before migrating to Compose shared settlement.
///         Reads rollup addresses from config.json via ROLLUP_NAME env var.
contract UpgradeToPortalInterop is Script {

    struct UpgradeConfig {
        address portalProxy;
        address proxyAdmin;
        address proxyAdminOwner;
        uint256 proofMaturityDelaySeconds;
    }

    UpgradeConfig public config;

    function run(bool dryRun) external {
        console.log("=================================================");
        console.log("Upgrading Portal to OptimismPortalInterop");
        console.log("=================================================");
        console.log("Rollup:", RollupConfig.rollupName());
        console.log("Mode:", dryRun ? "DRY RUN" : "LIVE");
        console.log("");

        // Load configuration
        loadConfig();

        // Validate current portal
        validatePortal();

        // Deploy new implementation
        address newImpl = deployPortalInteropImplementation();

        // Perform upgrade
        if (!dryRun) {
            upgradePortal(newImpl);
        } else {
            console.log("[DRY RUN] Would upgrade portal to:", newImpl);
        }

        console.log("\n=================================================");
        console.log("Upgrade Complete!");
        console.log("=================================================");
    }

    function loadConfig() internal {
        config.portalProxy = RollupConfig.portalProxy();
        config.proxyAdmin = RollupConfig.l1ProxyAdmin();
        config.proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();

        // Get proof maturity delay from current portal
        (bool success, bytes memory data) = config.portalProxy.staticcall(
            abi.encodeWithSignature("proofMaturityDelaySeconds()")
        );
        require(success, "Failed to read proofMaturityDelaySeconds");
        config.proofMaturityDelaySeconds = abi.decode(data, (uint256));

        console.log("Loaded configuration:");
        console.log("  Portal Proxy:", config.portalProxy);
        console.log("  ProxyAdmin:", config.proxyAdmin);
        console.log("  Owner:", config.proxyAdminOwner);
        console.log("  Proof Maturity Delay:", config.proofMaturityDelaySeconds);
        console.log("");
    }

    function validatePortal() internal view {
        console.log("Validating current portal...");

        // Check version
        (bool success, bytes memory data) = config.portalProxy.staticcall(
            abi.encodeWithSignature("version()")
        );
        require(success, "Failed to read portal version");
        string memory version = abi.decode(data, (string));
        console.log("  Current version:", version);

        // Check it's NOT already OptimismPortalInterop
        (success,) = config.portalProxy.staticcall(
            abi.encodeWithSignature("superRootsActive()")
        );
        require(!success, "Portal already has superRootsActive() - likely already OptimismPortalInterop");

        console.log("  Portal is standard OptimismPortal2 - upgrade needed");
        console.log("");
    }

    function deployPortalInteropImplementation() internal returns (address) {
        console.log("Deploying OptimismPortalInterop implementation...");

        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        OptimismPortalInterop newImpl = new OptimismPortalInterop({
            _proofMaturityDelaySeconds: config.proofMaturityDelaySeconds
        });
        vm.stopBroadcast();

        console.log("  New implementation deployed at:", address(newImpl));
        console.log("  Version:", newImpl.version());
        console.log("");

        return address(newImpl);
    }

    function upgradePortal(address newImpl) internal {
        console.log("Upgrading portal proxy...");

        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        IProxyAdmin(config.proxyAdmin).upgrade(
            payable(config.portalProxy),
            newImpl
        );
        vm.stopBroadcast();

        console.log("  Portal upgraded successfully");
        console.log("");

        // Verify upgrade
        (bool success, bytes memory data) = config.portalProxy.staticcall(
            abi.encodeWithSignature("superRootsActive()")
        );
        require(success, "Upgrade failed - superRootsActive() not callable");
        bool superRootsActive = abi.decode(data, (bool));
        console.log("  superRootsActive:", superRootsActive);
        require(!superRootsActive, "superRootsActive should be false after upgrade");

        console.log("  Upgrade verified!");
    }
}
