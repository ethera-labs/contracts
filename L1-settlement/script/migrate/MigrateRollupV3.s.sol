// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { MigrateRollupInput, MigrateRollupOutput } from "./MigrateRollupV3IO.sol";
import { ComposeDeployUtils } from "script/libraries/ComposeDeployUtils.sol";
import { ComposeConfig } from "script/libraries/ComposeConfig.sol";

// Interfaces
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IOptimismPortalInterop } from "interfaces/L1/IOptimismPortalInterop.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { IL1ERC721Bridge } from "interfaces/L1/IL1ERC721Bridge.sol";
import { IComposeAnchorStateRegistry } from "@ssv/src/interfaces/IComposeAnchorStateRegistry.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { IETHLockbox } from "interfaces/L1/IETHLockbox.sol";
import { ComposeETHLockbox } from "@ssv/src/ComposeETHLockbox.sol";

// Contracts to deploy
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";
import { L1CrossDomainMessenger } from "src/L1/L1CrossDomainMessenger.sol";
import { L1StandardBridge } from "src/L1/L1StandardBridge.sol";
import { L1ERC721Bridge } from "src/L1/L1ERC721Bridge.sol";

// Features
import { Features } from "src/L1/SystemConfig.sol";

/// @title MigrateRollupV3
/// @notice Script to execute Phase 2: Per-Rollup Migration (V3 → Compose)
/// @dev Migrates an existing OP Stack V3 rollup to V4 + Compose shared infrastructure
/// @dev This performs a FULL migration including contract upgrades and state migration
contract MigrateRollupV3 is Script {
    // NOTE: Struct fields MUST be in alphabetical order for vm.parseJson to work correctly
    struct ComposeDeployment {
        address anchorStateRegistry;
        address composeDisputeGame;
        address disputeGameFactory;
        address ethLockbox;
        uint256 l1ChainId;
        string l1Name;
        address proxyAdmin;
        address proxyAdminOwner;  // Compose ProxyAdmin owner address
        address superchainConfig;
    }
    
    // NOTE: Struct fields MUST be in alphabetical order for vm.parseJson to work correctly
    struct RollupConfig {
        address l1CrossDomainMessenger;
        address l1ERC721Bridge;
        address l1StandardBridge;
        address l1SystemConfigAddress;
        uint256 l2ChainId;
        OptimismPortalAddresses optimismPortal;
        ProxyAdminAddresses proxyAdmin;
    }
    
    struct OptimismPortalAddresses {
        address impl;   // ✅ alphabetical: 'i' before 'p'
        address proxy;
    }
    
    struct ProxyAdminAddresses {
        address impl;   // ✅ alphabetical: 'i' before 'o'
        address owner;
    }
    
    MigrateRollupInput public input;
    MigrateRollupOutput public output;
    
    bool public dryRun;
    
    /// @notice Entrypoint for migration
    /// @param rollup The rollup name (e.g., "rollup-a-stage")
    /// @param composeNetwork The compose network name (e.g., "hoodi-stage")
    /// @param _dryRun If true, simulate without broadcasting transactions
    function run(string memory rollup, string memory composeNetwork, bool _dryRun) public returns (MigrateRollupOutput) {
        dryRun = _dryRun;
        
        // Load configuration
        input = loadConfiguration(rollup, composeNetwork);
        output = new MigrateRollupOutput();
        
        // Pre-migration validation
        validatePreMigration();
        
        if (dryRun) {
            console.log("\n========================================");
            console.log("DRY RUN MODE - No transactions will be broadcast");
            console.log("========================================\n");
        }
        
        console.log("=================================================");
        console.log("Migrating Rollup to Compose (Phase 2)");
        console.log("Rollup:", rollup);
        console.log("Compose Network:", composeNetwork);
        console.log("L2 Chain ID:", input.l2ChainId());
        console.log("=================================================");
        
        // Execute migration steps
        step1_DeployImplementations();
        step2_UpgradeSystemConfig();
        step3_EnableETHLockboxFeature();
        step4_UpgradeOptimismPortalImpl();
        step5_InitializePortalUpgrade();
        step6_AuthorizePortalInLockbox();
        step7_MigrateETHLiquidity();
        step8_UpgradeBridges();
        step9_MigrateToSuperRoots();
        
        // Post-migration validation
        validatePostMigration();
        
        console.log("=================================================");
        console.log("Phase 2 Migration Complete!");
        console.log("=================================================");
        
        return output;
    }
    
    /// @notice Load migration configuration from JSON files
    function loadConfiguration(string memory rollup, string memory composeNetwork) internal returns (MigrateRollupInput) {
        MigrateRollupInput migrationInput = new MigrateRollupInput();
        
        string memory root = vm.projectRoot();
        
        // Load rollup-specific config from rollups directory
        string memory rollupPath = string.concat(root, "/script/config/rollups/", rollup, ".json");
        string memory rollupJson = vm.readFile(rollupPath);
        RollupConfig memory rollupConfig = abi.decode(vm.parseJson(rollupJson), (RollupConfig));
        
        console.log("Loaded rollup config from:", rollupPath);
        console.log("  L2 Chain ID:", rollupConfig.l2ChainId);
        console.log("  ProxyAdmin Owner:", rollupConfig.proxyAdmin.owner);
        
        // Load Phase 1 shared infrastructure addresses from compose directory
        string memory composePath = string.concat(root, "/script/config/compose/", composeNetwork, ".json");
        string memory composeJson = vm.readFile(composePath);
        ComposeDeployment memory composeConfig = abi.decode(vm.parseJson(composeJson), (ComposeDeployment));
        
        console.log("Loaded Compose config from:", composePath);
        console.log("  L1 Chain ID:", composeConfig.l1ChainId);
        console.log("  SuperchainConfig:", composeConfig.superchainConfig);
        
        // Populate migration input from rollup config
        migrationInput.set(migrationInput.l2ChainId.selector, rollupConfig.l2ChainId);
        migrationInput.set(migrationInput.rollupProxyAdmin.selector, rollupConfig.proxyAdmin.impl);
        migrationInput.set(migrationInput.rollupProxyAdminOwner.selector, rollupConfig.proxyAdmin.owner);
        migrationInput.set(migrationInput.systemConfig.selector, rollupConfig.l1SystemConfigAddress);
        migrationInput.set(migrationInput.optimismPortal.selector, rollupConfig.optimismPortal.proxy);
        migrationInput.set(migrationInput.l1CrossDomainMessenger.selector, rollupConfig.l1CrossDomainMessenger);
        migrationInput.set(migrationInput.l1StandardBridge.selector, rollupConfig.l1StandardBridge);
        migrationInput.set(migrationInput.l1ERC721Bridge.selector, rollupConfig.l1ERC721Bridge);
        
        // Populate migration input from compose config
        migrationInput.set(migrationInput.composeProxyAdminOwner.selector, composeConfig.proxyAdminOwner);

        migrationInput.set(
            migrationInput.composeSuperchainConfig.selector,
            composeConfig.superchainConfig
        );
        migrationInput.set(
            migrationInput.composeDisputeGameFactory.selector,
            composeConfig.disputeGameFactory
        );
        migrationInput.set(
            migrationInput.composeAnchorStateRegistry.selector,
            composeConfig.anchorStateRegistry
        );
        migrationInput.set(
            migrationInput.composeETHLockbox.selector,
            composeConfig.ethLockbox
        );
        
        // Load migration parameters from networks.toml (via ComposeConfig)
        migrationInput.set(
            migrationInput.proofMaturityDelaySeconds.selector,
            ComposeConfig.proofMaturityDelaySeconds()
        );
        
        return migrationInput;
    }
    
    /// @notice Step 1: Deploy new v4.x implementation contracts
    function step1_DeployImplementations() internal {
        console.log("\nStep 1: Deploying New Implementations...");
        
        address deployer = getDeployer();
        
        if (dryRun) {
            console.log("  [DRY RUN] Would deploy implementations");
            // In dry run, use placeholder addresses
            output.set(output.systemConfigImpl.selector, address(0x1001));
            output.set(output.optimismPortalImpl.selector, address(0x1002));
            output.set(output.l1CrossDomainMessengerImpl.selector, address(0x1003));
            output.set(output.l1StandardBridgeImpl.selector, address(0x1004));
            output.set(output.l1ERC721BridgeImpl.selector, address(0x1005));
            return;
        }
        
        vm.startBroadcast(deployer);
        
        // SystemConfig
        SystemConfig systemConfigImpl = new SystemConfig();
        ComposeDeployUtils.label(address(systemConfigImpl), "SystemConfigImpl");
        console.log("  SystemConfig impl:", address(systemConfigImpl));
        
        // OptimismPortalInterop (for Compose migration support)
        OptimismPortalInterop portalImpl = new OptimismPortalInterop(
            input.proofMaturityDelaySeconds()
        );
        ComposeDeployUtils.label(address(portalImpl), "OptimismPortalInteropImpl");
        console.log("  OptimismPortalInterop impl:", address(portalImpl));
        
        // L1CrossDomainMessenger
        L1CrossDomainMessenger xdmImpl = new L1CrossDomainMessenger();
        ComposeDeployUtils.label(address(xdmImpl), "L1CrossDomainMessengerImpl");
        console.log("  L1CrossDomainMessenger impl:", address(xdmImpl));
        
        // L1StandardBridge
        L1StandardBridge bridgeImpl = new L1StandardBridge();
        ComposeDeployUtils.label(address(bridgeImpl), "L1StandardBridgeImpl");
        console.log("  L1StandardBridge impl:", address(bridgeImpl));
        
        // L1ERC721Bridge
        L1ERC721Bridge erc721BridgeImpl = new L1ERC721Bridge();
        ComposeDeployUtils.label(address(erc721BridgeImpl), "L1ERC721BridgeImpl");
        console.log("  L1ERC721Bridge impl:", address(erc721BridgeImpl));
        
        vm.stopBroadcast();
        
        // Store addresses
        output.set(output.systemConfigImpl.selector, address(systemConfigImpl));
        output.set(output.optimismPortalImpl.selector, address(portalImpl));
        output.set(output.l1CrossDomainMessengerImpl.selector, address(xdmImpl));
        output.set(output.l1StandardBridgeImpl.selector, address(bridgeImpl));
        output.set(output.l1ERC721BridgeImpl.selector, address(erc721BridgeImpl));
    }
    
    /// @notice Step 2: Upgrade SystemConfig with l2ChainId and superchainConfig
    function step2_UpgradeSystemConfig() internal {
        console.log("\nStep 2: Upgrading SystemConfig...");
        
        IProxyAdmin proxyAdmin = IProxyAdmin(input.rollupProxyAdmin());
        
        bytes memory upgradeCalldata = abi.encodeCall(
            ISystemConfig.upgrade,
            (input.l2ChainId(), input.composeSuperchainConfig())
        );
        
        if (dryRun) {
            console.log("  [DRY RUN] Would upgrade SystemConfig");
            console.log("    Owner:", getRollupOwner());
            console.log("    Implementation:", output.systemConfigImpl());
            return;
        }
        
        vm.startBroadcast(getRollupOwner());
        proxyAdmin.upgradeAndCall(
            payable(address(input.systemConfig())),
            output.systemConfigImpl(),
            upgradeCalldata
        );
        vm.stopBroadcast();
        console.log("  SystemConfig upgraded successfully");
    }
    
    /// @notice Step 3: Enable ETH_LOCKBOX feature flag
    function step3_EnableETHLockboxFeature() internal {
        console.log("\nStep 3: Enabling ETH_LOCKBOX Feature...");
        
        if (dryRun) {
            console.log("  [DRY RUN] Would enable ETH_LOCKBOX feature");
            console.log("    Owner:", getRollupOwner());
            return;
        }
        
        vm.startBroadcast(getRollupOwner());
        input.systemConfig().setFeature(Features.ETH_LOCKBOX, true);
        vm.stopBroadcast();
        

        console.log("  ETH_LOCKBOX feature enabled");
    }
    
    /// @notice Step 4: Upgrade OptimismPortal2 implementation
    function step4_UpgradeOptimismPortalImpl() internal {
        console.log("\nStep 4: Upgrading OptimismPortal2 Implementation...");
        
        IProxyAdmin proxyAdmin = IProxyAdmin(input.rollupProxyAdmin());
        
        if (dryRun) {
            console.log("  [DRY RUN] Would upgrade OptimismPortal2 impl");
            console.log("    Owner:", getRollupOwner());
            console.log("    Implementation:", output.optimismPortalImpl());
            return;
        }
        
        vm.startBroadcast(getRollupOwner());
        proxyAdmin.upgrade(
            payable(address(input.optimismPortal())),
            output.optimismPortalImpl()
        );
        vm.stopBroadcast();
        
        console.log("  OptimismPortal2 impl upgraded");
    }
    
    /// @notice Step 5: SKIPPED - ASR and lockbox are set in Step 9 (migrateToSuperRoots)
    /// @dev The upgrade() function only sets ASR and lockbox but doesn't enable superRootsActive.
    ///      We use migrateToSuperRoots() instead which does all three atomically.
    function step5_InitializePortalUpgrade() internal {
        console.log("\nStep 5: Skipped (ASR/Lockbox set in Step 9)");
    }
    
    /// @notice Step 6: Authorize portal in shared lockbox
    function step6_AuthorizePortalInLockbox() internal {
        console.log("\nStep 6: Authorizing Portal in Lockbox...");
        
        // Note: This requires the Compose ProxyAdmin owner's private key
        if (dryRun) {
            console.log("  [DRY RUN] Would authorize portal in lockbox");
            console.log("    Compose Owner:", getComposeOwner());
            return;
        }
        
        vm.startBroadcast(getComposeOwner());
        console.log("Compose owner:", getComposeOwner());
        input.composeETHLockbox().authorizePortal(input.optimismPortal());
        vm.stopBroadcast();
        
        console.log("  Portal authorized in lockbox");
    }
    
    /// @notice Step 7: COMBINED WITH STEP 9
    /// @dev migrateLiquidity() requires ethLockbox to be set first, which happens in migrateToSuperRoots()
    ///      Per OptimismPortalInterop docs: these must be called atomically in the same transaction
    function step7_MigrateETHLiquidity() internal {
        console.log("\nStep 7: Combined with Step 9 (atomic migration)");
    }
    
    /// @notice Step 8: Upgrade all bridges
    function step8_UpgradeBridges() internal {
        console.log("\nStep 8: Upgrading Bridges...");
        
        IProxyAdmin proxyAdmin = IProxyAdmin(input.rollupProxyAdmin());
        
        if (dryRun) {
            console.log("  [DRY RUN] Would upgrade all bridges");
            console.log("    Owner:", getRollupOwner());
            return;
        }
        
        vm.startBroadcast(getRollupOwner());
        
        // L1CrossDomainMessenger
        proxyAdmin.upgradeAndCall(
            payable(address(input.l1CrossDomainMessenger())),
            output.l1CrossDomainMessengerImpl(),
            abi.encodeCall(IL1CrossDomainMessenger.upgrade, (input.systemConfig()))
        );
        console.log("  L1CrossDomainMessenger upgraded");
        
        // L1StandardBridge
        proxyAdmin.upgradeAndCall(
            payable(address(input.l1StandardBridge())),
            output.l1StandardBridgeImpl(),
            abi.encodeCall(IL1StandardBridge.upgrade, (input.systemConfig()))
        );
        console.log("  L1StandardBridge upgraded");
        
        // L1ERC721Bridge
        proxyAdmin.upgradeAndCall(
            payable(address(input.l1ERC721Bridge())),
            output.l1ERC721BridgeImpl(),
            abi.encodeCall(IL1ERC721Bridge.upgrade, (input.systemConfig()))
        );
        console.log("  L1ERC721Bridge upgraded");
        
        vm.stopBroadcast();
    }
    
    /// @notice Step 9: Migrate to Super Roots + Migrate ETH Liquidity (atomic)
    /// @dev These MUST be in the same transaction per OptimismPortalInterop contract docs
    function step9_MigrateToSuperRoots() internal {
        console.log("\nStep 9: Migrating to Super Roots + ETH Liquidity (atomic)...");
        
        uint256 portalBalance = address(input.optimismPortal()).balance;
        console.log("  Portal ETH balance:", portalBalance);
        
        if (dryRun) {
            console.log("  [DRY RUN] Would migrate to Super Roots and transfer ETH");
            console.log("    Owner:", getRollupOwner());
            return;
        }
        
        IOptimismPortalInterop portal = IOptimismPortalInterop(payable(address(input.optimismPortal())));
        
        vm.startBroadcast(getRollupOwner());
        
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
        
        // Verify all addresses are set
        require(input.l2ChainId() != 0, "L2 Chain ID not set");
        require(address(input.systemConfig()) != address(0), "SystemConfig not set");
        require(address(input.optimismPortal()) != address(0), "OptimismPortal not set");
        require(address(input.l1CrossDomainMessenger()) != address(0), "L1CrossDomainMessenger not set");
        require(address(input.l1StandardBridge()) != address(0), "L1StandardBridge not set");
        require(address(input.l1ERC721Bridge()) != address(0), "L1ERC721Bridge not set");
        require(address(input.composeSuperchainConfig()) != address(0), "Compose SuperchainConfig not set");
        require(address(input.composeAnchorStateRegistry()) != address(0), "Compose ASR not set");
        require(address(input.composeETHLockbox()) != address(0), "Compose ETHLockbox not set");
        
        console.log("  All required addresses are set");
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
        
        // Verify SystemConfig upgrade
        require(
            input.systemConfig().l2ChainId() == input.l2ChainId(),
            "SystemConfig l2ChainId mismatch"
        );
        require(
            address(input.systemConfig().superchainConfig()) == address(input.composeSuperchainConfig()),
            "SystemConfig superchainConfig mismatch"
        );
        console.log("  SystemConfig: OK");
        
        // Verify ETH_LOCKBOX feature
        require(
            input.systemConfig().isFeatureEnabled(Features.ETH_LOCKBOX),
            "ETH_LOCKBOX feature not enabled"
        );
        console.log("  ETH_LOCKBOX feature: OK");
        
        // Verify Portal upgrade
        require(
            address(input.optimismPortal().anchorStateRegistry()) == address(input.composeAnchorStateRegistry()),
            "Portal ASR mismatch"
        );
        require(
            address(input.optimismPortal().ethLockbox()) == address(input.composeETHLockbox()),
            "Portal lockbox mismatch"
        );
        console.log("  Portal upgrade: OK");
        
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
    
    /// @notice Get the deployer account (for implementation deployments)
    function getDeployer() internal view returns (address) {
        return msg.sender;
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
