// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {ComposePortal} from "src/l1/ComposePortal.sol";
import {IL1DepositWhitelist} from "src/l1/interfaces/IL1DepositWhitelist.sol";
import {ComposeConfig} from "script/l1/libraries/ComposeConfig.sol";
import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";

/// @title UpgradeToPortalInterop
/// @notice Upgrades a standard OptimismPortal2 (v5.x) or upstream interop portal to ComposePortal.
///         Required before migrating to Compose shared settlement when running this step standalone.
///         Reads rollup addresses from config.json via ROLLUP_NAME env var.
contract UpgradeToPortalInterop is Script {
    struct UpgradeConfig {
        address portalProxy;
        address proxyAdmin;
        address proxyAdminOwner;
        address depositWhitelist;
        uint256 proofMaturityDelaySeconds;
    }

    UpgradeConfig public config;
    bool internal alreadyWhitelistAware;

    function run(bool dryRun) external {
        console.log("=================================================");
        console.log("Upgrading Portal to ComposePortal");
        console.log("=================================================");
        console.log("Rollup:", RollupConfig.rollupName());
        console.log("Mode:", dryRun ? "DRY RUN" : "LIVE");
        console.log("");

        // Load configuration
        loadConfig();

        // Validate current portal
        validatePortal();
        if (alreadyWhitelistAware) {
            console.log("Portal already has expected deposit whitelist. Nothing to do.");
            return;
        }

        // Deploy new implementation
        address newImpl = deployComposePortalImplementation(dryRun);

        // Perform upgrade
        if (!dryRun) {
            upgradePortal(newImpl);
        } else {
            console.log("[DRY RUN] Would upgrade portal to a new ComposePortal implementation");
            console.log("[DRY RUN] Would call initializeDepositWhitelist with:", config.depositWhitelist);
        }

        console.log("\n=================================================");
        console.log("Upgrade Complete!");
        console.log("=================================================");
    }

    function loadConfig() internal {
        config.portalProxy = RollupConfig.portalProxy();
        config.proxyAdmin = RollupConfig.l1ProxyAdmin();
        config.proxyAdminOwner = RollupConfig.l1ProxyAdminOwner();
        config.depositWhitelist = ComposeConfig.depositWhitelist();

        // Get proof maturity delay from current portal
        (bool success, bytes memory data) = config.portalProxy.staticcall(abi.encodeWithSignature("proofMaturityDelaySeconds()"));
        require(success, "Failed to read proofMaturityDelaySeconds");
        config.proofMaturityDelaySeconds = abi.decode(data, (uint256));

        console.log("Loaded configuration:");
        console.log("  Portal Proxy:", config.portalProxy);
        console.log("  ProxyAdmin:", config.proxyAdmin);
        console.log("  Owner:", config.proxyAdminOwner);
        console.log("  Deposit Whitelist:", config.depositWhitelist);
        console.log("  Proof Maturity Delay:", config.proofMaturityDelaySeconds);
        console.log("");
    }

    function validatePortal() internal {
        console.log("Validating current portal...");

        // Check version
        (bool success, bytes memory data) = config.portalProxy.staticcall(abi.encodeWithSignature("version()"));
        require(success, "Failed to read portal version");
        string memory version = abi.decode(data, (string));
        console.log("  Current version:", version);

        (bool whitelistOk, bytes memory whitelistData) = config.portalProxy.staticcall(abi.encodeWithSignature("depositWhitelist()"));
        if (whitelistOk && whitelistData.length == 32 && abi.decode(whitelistData, (address)) == config.depositWhitelist) {
            alreadyWhitelistAware = true;
            console.log("  Portal already wired to deposit whitelist");
            console.log("");
            return;
        }

        // Check whether the current implementation already exposes interop state.
        (success,) = config.portalProxy.staticcall(abi.encodeWithSignature("superRootsActive()"));
        if (success) {
            console.log("  Portal is interop-compatible but whitelist is not wired - upgrade needed");
        } else {
            console.log("  Portal is standard OptimismPortal2 - upgrade needed");
        }
        console.log("");
    }

    function deployComposePortalImplementation(bool dryRun) internal returns (address) {
        console.log("Deploying ComposePortal implementation...");

        if (dryRun) {
            return address(0);
        }

        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        ComposePortal newImpl = new ComposePortal({_proofMaturityDelaySeconds: config.proofMaturityDelaySeconds});
        vm.stopBroadcast();

        console.log("  New implementation deployed at:", address(newImpl));
        console.log("  Version:", newImpl.version());
        console.log("");

        return address(newImpl);
    }

    function upgradePortal(address newImpl) internal {
        console.log("Upgrading portal proxy...");

        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        IProxyAdmin(config.proxyAdmin)
            .upgradeAndCall(
                payable(config.portalProxy), newImpl, abi.encodeCall(ComposePortal.initializeDepositWhitelist, (IL1DepositWhitelist(config.depositWhitelist)))
            );
        vm.stopBroadcast();

        console.log("  Portal upgraded successfully with default-deny deposit whitelist");
        console.log("");

        // Verify upgrade
        (bool success, bytes memory data) = config.portalProxy.staticcall(abi.encodeWithSignature("superRootsActive()"));
        require(success, "Upgrade failed - superRootsActive() not callable");
        bool superRootsActive = abi.decode(data, (bool));
        console.log("  superRootsActive:", superRootsActive);

        (success, data) = config.portalProxy.staticcall(abi.encodeWithSignature("depositWhitelist()"));
        require(success, "Upgrade failed - depositWhitelist() not callable");
        require(abi.decode(data, (address)) == config.depositWhitelist, "depositWhitelist mismatch");
        console.log("  depositWhitelist:", config.depositWhitelist);

        console.log("  Upgrade verified!");
    }
}
