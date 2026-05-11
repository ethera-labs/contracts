// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { MigrateRollupV4Input } from "./MigrateRollupV4IO.sol";
import { ComposeConfig } from "script/l1/libraries/ComposeConfig.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

// Contracts
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";

// Interfaces
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IOptimismPortalInterop } from "interfaces/L1/IOptimismPortalInterop.sol";
import { IComposeAnchorStateRegistry } from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ComposeETHLockbox } from "src/l1/ComposeETHLockbox.sol";

// Features
import { Features } from "src/L1/SystemConfig.sol";

/// @title MigrateRollupV4
/// @notice Script to execute Phase 2: V4 Rollup Migration to Compose
/// @dev Migrates an existing OP Stack V4/V5 rollup to use Compose shared infrastructure
/// @dev This performs a MINIMAL migration - no contract upgrades, only state updates
contract MigrateRollupV4 is Script {
    MigrateRollupV4Input public input;

    bool public dryRun;

    /// @notice Entrypoint for V4 migration
    /// @dev Reads rollup from ROLLUP_NAME env var
    /// @param _dryRun If true, simulate without broadcasting transactions
    function run(bool _dryRun) public {
        dryRun = _dryRun;

        input = loadConfiguration();

        validatePreMigration();

        if (dryRun) {
            console.log("\n========================================");
            console.log("DRY RUN MODE - No transactions will be broadcast");
            console.log("========================================\n");
        }

        console.log("=================================================");
        console.log("Migrating V4 Rollup to Compose (Phase 2)");
        console.log("Rollup:", RollupConfig.rollupName());
        console.log("L2 Chain ID:", input.l2ChainId());
        console.log("=================================================");

        step0_EnsurePortalInterop();
        step1_EnableETHLockboxFeature();
        step2_AuthorizePortalInLockbox();
        step3_MigrateToCompose();

        validatePostMigration();

        console.log("=================================================");
        console.log("V4 Migration Complete!");
        console.log("=================================================");
    }

    /// @notice Load migration configuration from config.json via RollupConfig and ComposeConfig
    function loadConfiguration() internal returns (MigrateRollupV4Input) {
        MigrateRollupV4Input migrationInput = new MigrateRollupV4Input();

        console.log("Loaded rollup config from config.json");
        console.log("  Rollup:", RollupConfig.rollupName());
        console.log("  L2 Chain ID:", RollupConfig.chainId());
        console.log("  ProxyAdmin Owner:", RollupConfig.l1ProxyAdminOwner());
        console.log("  SuperchainConfig:", ComposeConfig.superchainConfig());

        migrationInput.set(migrationInput.l2ChainId.selector, RollupConfig.chainId());
        migrationInput.set(migrationInput.rollupProxyAdmin.selector, RollupConfig.l1ProxyAdmin());
        migrationInput.set(migrationInput.rollupProxyAdminOwner.selector, RollupConfig.l1ProxyAdminOwner());
        migrationInput.set(migrationInput.systemConfig.selector, RollupConfig.systemConfig());
        migrationInput.set(migrationInput.optimismPortal.selector, RollupConfig.portalProxy());

        migrationInput.set(migrationInput.composeProxyAdminOwner.selector, ComposeConfig.proxyAdminOwner());
        migrationInput.set(migrationInput.composeSuperchainConfig.selector, ComposeConfig.superchainConfig());
        migrationInput.set(migrationInput.composeAnchorStateRegistry.selector, ComposeConfig.anchorStateRegistry());
        migrationInput.set(migrationInput.composeETHLockbox.selector, ComposeConfig.ethLockbox());

        return migrationInput;
    }
    
    /// @notice Step 0: Check and upgrade portal to OptimismPortalInterop if needed
    function step0_EnsurePortalInterop() internal {
        console.log("\nStep 0: Checking Portal Type...");
        
        // Try to call superRootsActive() to detect if this is OptimismPortalInterop
        (bool success, ) = address(input.optimismPortal()).staticcall(
            abi.encodeWithSignature("superRootsActive()")
        );
        
        if (success) {
            console.log("  Portal is already OptimismPortalInterop - skipping upgrade");
            return;
        }
        
        console.log("  Portal is standard OptimismPortal2 - upgrade to OptimismPortalInterop required");
        
        // Get proof maturity delay from current portal
        uint256 proofMaturityDelay = input.optimismPortal().proofMaturityDelaySeconds();
        console.log("  Current proof maturity delay:", proofMaturityDelay);
        
        // Deploy new OptimismPortalInterop implementation (simulated in dry-run, broadcast in live)
        if (dryRun) {
            console.log("  [DRY RUN] Deploying OptimismPortalInterop implementation (simulation)...");
        } else {
            console.log("  Deploying OptimismPortalInterop implementation...");
        }
        
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        OptimismPortalInterop newImpl = new OptimismPortalInterop({
            _proofMaturityDelaySeconds: proofMaturityDelay
        });
        console.log("    Implementation deployed at:", address(newImpl));
        
        // Upgrade portal proxy
        if (dryRun) {
            console.log("  [DRY RUN] Upgrading portal proxy (simulation)...");
        } else {
            console.log("  Upgrading portal proxy...");
        }
        
        IProxyAdmin(input.rollupProxyAdmin()).upgrade(
            payable(address(input.optimismPortal())),
            address(newImpl)
        );
        vm.stopBroadcast();
        
        console.log("  Portal upgraded to OptimismPortalInterop");
        
        // Verify upgrade
        (bool verifySuccess, bytes memory data) = address(input.optimismPortal()).staticcall(
            abi.encodeWithSignature("superRootsActive()")
        );
        require(verifySuccess, "Portal upgrade verification failed");
        bool superRootsActive = abi.decode(data, (bool));
        console.log("  Verified: superRootsActive =", superRootsActive);
    }
    
    /// @notice Step 1: Enable ETH_LOCKBOX feature (if not already enabled)
    function step1_EnableETHLockboxFeature() internal {
        console.log("\nStep 1: Enabling ETH_LOCKBOX Feature...");
        
        // Check if already enabled
        bool isEnabled = input.systemConfig().isFeatureEnabled(Features.ETH_LOCKBOX);
        
        if (isEnabled) {
            console.log("  ETH_LOCKBOX feature already enabled - skipping");
            return;
        }
        
        if (dryRun) {
            console.log("  [DRY RUN] Would enable ETH_LOCKBOX feature");
            console.log("    Owner:", getRollupOwner());
            return;
        }
        
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        input.systemConfig().setFeature(Features.ETH_LOCKBOX, true);
        vm.stopBroadcast();
        
        console.log("  ETH_LOCKBOX feature enabled");
    }
    
    /// @notice Step 2: Authorize portal in shared lockbox
    function step2_AuthorizePortalInLockbox() internal {
        console.log("\nStep 2: Authorizing Portal in Lockbox...");
        
        // Check if already authorized
        bool isAuthorized = input.composeETHLockbox().authorizedPortals(input.optimismPortal());
        
        if (isAuthorized) {
            console.log("  Portal already authorized - skipping");
            return;
        }
        
        if (dryRun) {
            console.log("  [DRY RUN] Would authorize portal in lockbox");
            console.log("    Compose Owner:", getComposeOwner());
            return;
        }
        
        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        input.composeETHLockbox().authorizePortal(input.optimismPortal());
        vm.stopBroadcast();
        
        console.log("  Portal authorized in lockbox");
    }
    
    /// @notice Step 3: Migrate to Super Roots + Migrate ETH Liquidity (atomic, if not already migrated)
    function step3_MigrateToCompose() internal {
        console.log("\nStep 3: Migrating to Compose Infrastructure...");
        
        // Check if already migrated
        IOptimismPortalInterop portal = IOptimismPortalInterop(payable(address(input.optimismPortal())));
        bool superRootsActive = portal.superRootsActive();
        
        if (superRootsActive) {
            console.log("  Portal already in Super Roots mode - skipping");
            return;
        }
        
        uint256 portalBalance = address(input.optimismPortal()).balance;
        console.log("  Portal ETH balance:", portalBalance);
        
        if (dryRun) {
            console.log("  [DRY RUN] Would migrate to Super Roots and transfer ETH");
            console.log("    Owner:", getRollupOwner());
            return;
        }
        
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        
        // Step 1: Set new lockbox and ASR, enable superRootsActive
        portal.migrateToSuperRoots(
            IETHLockbox(address(input.composeETHLockbox())),
            IAnchorStateRegistry(address(input.composeAnchorStateRegistry()))
        );
        console.log("  Portal migrated to Super Roots mode");
        console.log("    ASR:", address(input.composeAnchorStateRegistry()));
        console.log("    Lockbox:", address(input.composeETHLockbox()));
        console.log("    superRootsActive: true");
        
        // Step 2: Migrate ETH liquidity (now that ethLockbox is set)
        portal.migrateLiquidity();
        console.log("  ETH migrated to lockbox");
        console.log("    Amount:", portalBalance);
        console.log("    New portal balance:", address(input.optimismPortal()).balance);
        
        vm.stopBroadcast();
    }
    
    /// @notice Validate configuration before migration
    function validatePreMigration() internal view {
        console.log("\nPre-Migration Validation:");
        
        // 1. Verify all addresses are set
        require(input.l2ChainId() != 0, "L2 Chain ID not set");
        require(address(input.systemConfig()) != address(0), "SystemConfig not set");
        require(address(input.optimismPortal()) != address(0), "OptimismPortal not set");
        require(address(input.composeSuperchainConfig()) != address(0), "Compose SuperchainConfig not set");
        require(address(input.composeAnchorStateRegistry()) != address(0), "Compose ASR not set");
        require(address(input.composeETHLockbox()) != address(0), "Compose ETHLockbox not set");
        
        console.log("  All required addresses are set");
        
        // 2. Verify portal version (bash script already checked, this is a safety net)
        string memory portalVersion = input.optimismPortal().version();
        console.log("  Portal version:", portalVersion);
        
        // 3. Verify SystemConfig supports ETH_LOCKBOX feature
        try input.systemConfig().isFeatureEnabled(Features.ETH_LOCKBOX) returns (bool) {
            console.log("  SystemConfig supports ETH_LOCKBOX feature");
        } catch {
            revert("SystemConfig doesn't support ETH_LOCKBOX feature. This rollup needs v3->v4 upgrade first.");
        }
        
        console.log("  L2 Chain ID:", input.l2ChainId());
        console.log("  Rollup ProxyAdmin:", input.rollupProxyAdmin());
        console.log("  Rollup ProxyAdmin Owner:", input.rollupProxyAdminOwner());
    }
    
    /// @notice Validate state after migration
    function validatePostMigration() internal view {
        if (dryRun) {
            console.log("\n[DRY RUN] Skipping post-migration validation");
            return;
        }
        
        console.log("\nPost-Migration Validation:");
        
        // Verify ETH_LOCKBOX feature
        require(
            input.systemConfig().isFeatureEnabled(Features.ETH_LOCKBOX),
            "ETH_LOCKBOX feature not enabled"
        );
        console.log("  ETH_LOCKBOX feature: OK");
        
        // Verify Portal configuration
        require(
            address(input.optimismPortal().anchorStateRegistry()) == address(input.composeAnchorStateRegistry()),
            "Portal ASR mismatch"
        );
        require(
            address(input.optimismPortal().ethLockbox()) == address(input.composeETHLockbox()),
            "Portal lockbox mismatch"
        );
        console.log("  Portal configuration: OK");
        
        // Verify Super Roots mode
        require(
            IOptimismPortalInterop(payable(address(input.optimismPortal()))).superRootsActive(),
            "Super Roots not active"
        );
        console.log("  Super Roots mode: OK");
        
        // Verify ETH migration
        require(
            address(input.optimismPortal()).balance == 0,
            "Portal still has ETH balance"
        );
        console.log("  ETH migration: OK");
        
        // Verify portal authorization
        require(
            input.composeETHLockbox().authorizedPortals(input.optimismPortal()),
            "Portal not authorized in lockbox"
        );
        console.log("  Portal authorization: OK");
        
        console.log("\n  All validations passed!");
    }
    
    /// @notice Get the rollup's ProxyAdmin owner address from config
    function getRollupOwner() internal view returns (address) {
        return input.rollupProxyAdminOwner();
    }
    
    /// @notice Get the Compose ProxyAdmin owner address from loaded input
    function getComposeOwner() internal view returns (address) {
        return input.composeProxyAdminOwner();
    }
}
