// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Proxies
import { Proxy } from "src/universal/Proxy.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

// Compose contracts
import { ComposePortal } from "src/ComposePortal.sol";
import { ComposeL1Bridge, IComposePortalERC20 } from "src/ComposeL1Bridge.sol";
import { ComposeERC20Lockbox } from "src/ComposeERC20Lockbox.sol";

// Interfaces
import { IComposePortal } from "src/interfaces/IComposePortal.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";

import { Features } from "src/L1/SystemConfig.sol";

/// @title UpgradeToComposeBridge
/// @notice Per-rollup L1 upgrade: swap OptimismPortal impl for ComposePortal, deploy
///         ComposeL1Bridge proxy, wire shared ComposeERC20Lockbox. Assumes rollup already
///         migrated to Compose V4 (Interop portal + shared ETHLockbox + Compose ASR/DGF).
///         All steps idempotent; re-runnable.
contract UpgradeToComposeBridge is Script {
    /// @dev Must be in alphabetical order for vm.parseJson.
    struct Cfg {
        address composeAdminOwner;
        address composeProxyAdmin;
        address erc20LockboxProxy; // 0 = deploy inline
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

    function run(string memory configPath, bool _dryRun) external {
        dryRun = _dryRun;
        _loadConfig(configPath);

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

        _broadcastStart(cfg.rollupAdminOwner);
        composePortalImpl = address(new ComposePortal(delay));
        composeL1BridgeImpl = address(new ComposeL1Bridge());
        _broadcastStop();

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

        _broadcastStart(cfg.composeAdminOwner);
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
        _broadcastStop();

        erc20Lockbox = address(proxy);
        console.log("  deployed impl       :", impl);
        console.log("  deployed proxy      :", erc20Lockbox);
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

        _broadcastStart(cfg.rollupAdminOwner);
        IProxyAdmin(cfg.rollupProxyAdmin).upgradeAndCall(
            payable(cfg.portalProxy),
            composePortalImpl,
            initData
        );
        _broadcastStop();

        console.log("  portal upgraded -> ComposePortal, initializeCompose called");
    }

    function _step4_deployBridgeProxy() internal {
        console.log("\n[4] Deploy bridge proxy");
        _broadcastStart(cfg.rollupAdminOwner);
        Proxy p = new Proxy(cfg.rollupProxyAdmin);
        _broadcastStop();
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

        _broadcastStart(cfg.rollupAdminOwner);
        IProxyAdmin(cfg.rollupProxyAdmin).upgradeAndCall(
            payable(bridgeProxy),
            composeL1BridgeImpl,
            initData
        );
        _broadcastStop();

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

        _broadcastStart(cfg.rollupAdminOwner);
        ComposePortal(payable(cfg.portalProxy)).authorizeBridge(bridgeProxy);
        _broadcastStop();

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

        _broadcastStart(cfg.composeAdminOwner);
        ComposeERC20Lockbox(erc20Lockbox).authorizePortal(IComposePortal(cfg.portalProxy));
        _broadcastStop();

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
            keccak256(bytes(portal.version())) == keccak256(bytes("5.0.0-compose")),
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

    function _loadConfig(string memory configPath) internal {
        string memory json = vm.readFile(configPath);
        cfg = abi.decode(vm.parseJson(json), (Cfg));
    }

    function _broadcastStart(address who) internal {
        if (dryRun) {
            console.log("    [DRY RUN] broadcaster:", who);
            return;
        }
        vm.startBroadcast(who);
    }

    function _broadcastStop() internal {
        if (dryRun) return;
        vm.stopBroadcast();
    }

    function _banner() internal view {
        console.log("============================================");
        console.log("Upgrade to Compose Bridge");
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

    function _summary() internal view {
        console.log("\n============================================");
        console.log("Done");
        console.log("============================================");
        console.log("  composePortalImpl  :", composePortalImpl);
        console.log("  composeL1BridgeImpl:", composeL1BridgeImpl);
        console.log("  erc20Lockbox       :", erc20Lockbox);
        console.log("  bridgeProxy        :", bridgeProxy);
        console.log("");
        console.log("Next step: wire L2 bridge address once L2 deploys:");
        console.log("  ComposeL1Bridge(bridgeProxy).setOtherBridge(l2BridgeAddr)");
    }
}
