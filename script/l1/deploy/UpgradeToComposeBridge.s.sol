// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Proxies
import { Proxy } from "src/universal/Proxy.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

// Compose contracts
import { ComposePortal } from "src/l1/ComposePortal.sol";
import { ComposeL1Bridge, IComposePortalERC20 } from "src/l1/ComposeL1Bridge.sol";
import { ComposeERC20Lockbox } from "src/l1/ComposeERC20Lockbox.sol";

// Interfaces
import { IComposePortal } from "src/l1/interfaces/IComposePortal.sol";
import { IComposeERC20Lockbox } from "src/l1/interfaces/IComposeERC20Lockbox.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";

import { Features } from "src/L1/SystemConfig.sol";
import { ComposeConfig } from "script/l1/libraries/ComposeConfig.sol";
import { RollupConfig } from "script/l2/libraries/RollupConfig.sol";

/// @title UpgradeToComposeBridge
/// @notice Per-rollup L1 upgrade: swap OptimismPortal impl for ComposePortal, deploy
///         ComposeL1Bridge proxy, wire shared ComposeERC20Lockbox. Assumes rollup already
///         migrated to Compose V4 (Interop portal + shared ETHLockbox + Compose ASR/DGF).
contract UpgradeToComposeBridge is Script {
    struct Cfg {
        address composeAdminOwner;
        address composeProxyAdmin;
        address erc20LockboxProxy;
        address l1Xdm;
        address portalProxy;
        address rollupAdminOwner;
        address rollupProxyAdmin;
        address superchainConfig;
        address systemConfig;
    }

    Cfg internal cfg;
    bool internal dryRun;

    // Computed / deployed
    address public composePortalImpl;
    address public composeL1BridgeImpl;
    address public bridgeProxy;
    address public erc20Lockbox;

    function run(bool _dryRun) external {
        dryRun = _dryRun;
        _loadConfig();

        _banner();

        _step0_preflight();
        _step1_deployImpls();
        _step2_ensureErc20Lockbox();
        _step3_upgradePortalAndInit();
        _step4_deployBridgeProxy();
        _step5_initBridge();
        _step6_authorizeBridge();
        _step7_authorizePortal();
        _step8_postflight();

        _summary();
    }

    // ---------------------------------------------------------------------------------------------
    // Steps
    // ---------------------------------------------------------------------------------------------

    function _step0_preflight() internal view {
        console.log("\n[0] Preflight");

        require(cfg.portalProxy != address(0), "portalProxy=0");
        require(cfg.rollupProxyAdmin != address(0), "rollupProxyAdmin=0");
        require(cfg.rollupAdminOwner != address(0), "rollupAdminOwner=0");
        require(cfg.composeAdminOwner != address(0), "composeAdminOwner=0");
        require(cfg.composeProxyAdmin != address(0), "composeProxyAdmin=0");
        require(cfg.superchainConfig != address(0), "superchainConfig=0");
        require(cfg.l1Xdm != address(0), "l1Xdm=0");
        require(cfg.systemConfig != address(0), "systemConfig=0");

        require(
            ISystemConfig(cfg.systemConfig).isFeatureEnabled(Features.ETH_LOCKBOX),
            "ETH_LOCKBOX feature not enabled"
        );

        IOptimismPortal2 portal = IOptimismPortal2(payable(cfg.portalProxy));
        require(address(portal.ethLockbox()) != address(0), "portal.ethLockbox=0");
        require(address(portal.anchorStateRegistry()) != address(0), "portal.asr=0");
        console.log("  portal.version()          :", portal.version());
        console.log("  portal.ethLockbox()       :", address(portal.ethLockbox()));
        console.log("  portal.anchorStateRegistry:", address(portal.anchorStateRegistry()));
    }

    function _step1_deployImpls() internal {
        console.log("\n[1] Deploy impls");
        uint256 delay = IOptimismPortal2(payable(cfg.portalProxy)).proofMaturityDelaySeconds();
        console.log("  proofMaturityDelay:", delay);

        _broadcastRollup();
        composePortalImpl = address(new ComposePortal(delay));
        composeL1BridgeImpl = address(new ComposeL1Bridge());
        vm.stopBroadcast();

        console.log("  composePortalImpl   :", composePortalImpl);
        console.log("  composeL1BridgeImpl :", composeL1BridgeImpl);
    }

    function _step2_ensureErc20Lockbox() internal {
        console.log("\n[2] ERC20 Lockbox");
        if (cfg.erc20LockboxProxy != address(0)) {
            erc20Lockbox = cfg.erc20LockboxProxy;
            console.log("  reusing existing    :", erc20Lockbox);
            return;
        }

        _broadcastCompose();
        address impl = address(new ComposeERC20Lockbox());
        Proxy proxy = new Proxy(cfg.composeProxyAdmin);
        IProxyAdmin(cfg.composeProxyAdmin).upgradeAndCall(
            payable(address(proxy)),
            impl,
            abi.encodeCall(
                ComposeERC20Lockbox.initialize,
                (ISuperchainConfig(cfg.superchainConfig), new IComposePortal[](0))
            )
        );
        vm.stopBroadcast();

        erc20Lockbox = address(proxy);
        console.log("  deployed impl       :", impl);
        console.log("  deployed proxy      :", erc20Lockbox);

        vm.writeJson(vm.toString(erc20Lockbox), "config.json", ".l1.deployed.erc20LockboxProxy");
        console.log("  saved to config.json [l1.deployed.erc20LockboxProxy]");
    }

    function _step3_upgradePortalAndInit() internal {
        console.log("\n[3] Upgrade portal + initializeCompose");

        // Idempotency: if erc20Lockbox already set on portal, assume upgrade ran.
        (bool ok, bytes memory ret) = cfg.portalProxy.staticcall(
            abi.encodeWithSignature("erc20Lockbox()")
        );
        if (ok && ret.length == 32 && abi.decode(ret, (address)) == erc20Lockbox) {
            console.log("  already upgraded & initialized - skip");
            return;
        }

        bytes memory initData = abi.encodeCall(
            ComposePortal.initializeCompose,
            (IComposeERC20Lockbox(erc20Lockbox))
        );

        _broadcastRollup();
        IProxyAdmin(cfg.rollupProxyAdmin).upgradeAndCall(
            payable(cfg.portalProxy),
            composePortalImpl,
            initData
        );
        vm.stopBroadcast();

        console.log("  portal upgraded -> ComposePortal, initializeCompose called");
    }

    function _step4_deployBridgeProxy() internal {
        console.log("\n[4] Deploy bridge proxy");
        _broadcastRollup();
        Proxy p = new Proxy(cfg.rollupProxyAdmin);
        vm.stopBroadcast();
        bridgeProxy = address(p);
        console.log("  bridgeProxy:", bridgeProxy);
    }

    function _step5_initBridge() internal {
        console.log("\n[5] Init bridge");

        bytes memory initData = abi.encodeCall(
            ComposeL1Bridge.initialize,
            (
                ICrossDomainMessenger(cfg.l1Xdm),
                address(0), // otherBridge: wire later via setOtherBridge
                ISuperchainConfig(cfg.superchainConfig),
                IComposeERC20Lockbox(erc20Lockbox),
                IComposePortalERC20(cfg.portalProxy)
            )
        );

        _broadcastRollup();
        IProxyAdmin(cfg.rollupProxyAdmin).upgradeAndCall(
            payable(bridgeProxy),
            composeL1BridgeImpl,
            initData
        );
        vm.stopBroadcast();

        console.log("  bridge initialized (otherBridge=0, wire via setOtherBridge later)");
    }

    function _step6_authorizeBridge() internal {
        console.log("\n[6] portal.authorizeBridge(bridge)");
        (bool ok, bytes memory ret) = cfg.portalProxy.staticcall(
            abi.encodeWithSignature("authorizedBridges(address)", bridgeProxy)
        );
        if (ok && ret.length == 32 && abi.decode(ret, (bool))) {
            console.log("  already authorized - skip");
            return;
        }

        _broadcastRollup();
        ComposePortal(payable(cfg.portalProxy)).authorizeBridge(bridgeProxy);
        vm.stopBroadcast();

        console.log("  authorized");
    }

    function _step7_authorizePortal() internal {
        console.log("\n[7] lockbox.authorizePortal(portal)");
        (bool ok, bytes memory ret) = erc20Lockbox.staticcall(
            abi.encodeWithSignature("authorizedPortals(address)", cfg.portalProxy)
        );
        if (ok && ret.length == 32 && abi.decode(ret, (bool))) {
            console.log("  already authorized - skip");
            return;
        }

        _broadcastCompose();
        ComposeERC20Lockbox(erc20Lockbox).authorizePortal(IComposePortal(cfg.portalProxy));
        vm.stopBroadcast();

        console.log("  authorized");
    }

    function _step8_postflight() internal view {
        if (dryRun) {
            console.log("\n[8] Postflight skipped (dry run)");
            return;
        }

        console.log("\n[8] Postflight");

        ComposePortal portal = ComposePortal(payable(cfg.portalProxy));
        ComposeL1Bridge bridge = ComposeL1Bridge(payable(bridgeProxy));
        ComposeERC20Lockbox lb = ComposeERC20Lockbox(erc20Lockbox);

        require(
            keccak256(bytes(portal.version())) == keccak256(bytes("1.0.0-compose")),
            "portal.version mismatch"
        );
        require(address(portal.erc20Lockbox()) == erc20Lockbox, "portal.erc20Lockbox mismatch");
        require(portal.authorizedBridges(bridgeProxy), "portal.authorizedBridges false");

        require(lb.authorizedPortals(IComposePortal(cfg.portalProxy)), "lockbox.authorizedPortals false");

        require(address(bridge.messenger()) == cfg.l1Xdm, "bridge.messenger mismatch");
        require(address(bridge.erc20Lockbox()) == erc20Lockbox, "bridge.erc20Lockbox mismatch");
        require(address(bridge.superchainConfig()) == cfg.superchainConfig, "bridge.superchainConfig mismatch");
        require(bridge.otherBridge() == address(0), "bridge.otherBridge already set (expected 0)");

        console.log("  all checks passed");
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    function _loadConfig() internal {
        cfg.composeAdminOwner = ComposeConfig.proxyAdminOwner();
        cfg.composeProxyAdmin = ComposeConfig.proxyAdmin();
        cfg.erc20LockboxProxy = ComposeConfig.erc20LockboxProxy();
        cfg.l1Xdm = RollupConfig.l1CrossDomainMessenger();
        cfg.portalProxy = RollupConfig.portalProxy();
        cfg.rollupAdminOwner = RollupConfig.l1ProxyAdminOwner();
        cfg.rollupProxyAdmin = RollupConfig.l1ProxyAdmin();
        cfg.superchainConfig = ComposeConfig.superchainConfig();
        cfg.systemConfig = RollupConfig.systemConfig();
    }

    function _broadcastRollup() internal {
        if (dryRun) {
            vm.startPrank(cfg.rollupAdminOwner, cfg.rollupAdminOwner);
            return;
        }
        vm.startBroadcast(vm.envOr("ROLLUP_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
    }

    function _broadcastCompose() internal {
        if (dryRun) {
            vm.startPrank(cfg.composeAdminOwner, cfg.composeAdminOwner);
            return;
        }
        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
    }

    function _banner() internal view {
        console.log("============================================");
        console.log("Upgrade to Compose Bridge");
        console.log("  rollup             :", RollupConfig.rollupName());
        console.log("============================================");
        if (dryRun) console.log("[DRY RUN MODE]");
        console.log("  portalProxy        :", cfg.portalProxy);
        console.log("  rollupProxyAdmin   :", cfg.rollupProxyAdmin);
        console.log("  rollupAdminOwner   :", cfg.rollupAdminOwner);
        console.log("  composeProxyAdmin  :", cfg.composeProxyAdmin);
        console.log("  composeAdminOwner  :", cfg.composeAdminOwner);
        console.log("  superchainConfig   :", cfg.superchainConfig);
        console.log("  systemConfig       :", cfg.systemConfig);
        console.log("  l1Xdm              :", cfg.l1Xdm);
        console.log(
            "  erc20LockboxProxy  :",
            cfg.erc20LockboxProxy == address(0) ? address(0) : cfg.erc20LockboxProxy
        );
    }

    function _summary() internal {
        string memory rollupKey = string.concat('.rollups["', RollupConfig.rollupName(), '"].l1.composeBridge');
        vm.writeJson(vm.toString(bridgeProxy), "config.json", rollupKey);
        console.log("  saved to config.json [%s]", rollupKey);

        console.log("\n============================================");
        console.log("Done");
        console.log("============================================");
        console.log("  composePortalImpl  :", composePortalImpl);
        console.log("  composeL1BridgeImpl:", composeL1BridgeImpl);
        console.log("  erc20Lockbox       :", erc20Lockbox);
        console.log("  bridgeProxy        :", bridgeProxy);
        console.log("");
    }
}
