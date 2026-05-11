// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { Proxy } from "src/universal/Proxy.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ComposeETHLockbox } from "src/l1/ComposeETHLockbox.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 as IOptimismPortal } from "interfaces/L1/IOptimismPortal2.sol";

/// @title DeployComposeETHLockbox
/// @notice Deploy a standalone `ComposeETHLockbox` proxy, wired into an existing ProxyAdmin
///         and SuperchainConfig. Use when shared infra was deployed without an ETHLockbox.
///         Initializes with an empty portal list — authorize portals later per-rollup.
/// Env:
///   PROXY_ADMIN          existing ComposeProxyAdmin contract
///   PROXY_ADMIN_OWNER    owner of the ProxyAdmin (signs the upgradeAndCall)
///   SUPERCHAIN_CONFIG    existing SuperchainConfig proxy
contract DeployComposeETHLockbox is Script {
    function run() external returns (address proxyAddr, address implAddr) {
        address proxyAdmin       = vm.envAddress("PROXY_ADMIN");
        address proxyAdminOwner  = vm.envAddress("PROXY_ADMIN_OWNER");
        address superchainConfig = vm.envAddress("SUPERCHAIN_CONFIG");

        vm.startBroadcast(proxyAdminOwner);

        ComposeETHLockbox impl = new ComposeETHLockbox();
        implAddr = address(impl);
        console.log("\n[1] ComposeETHLockbox impl :", implAddr);

        Proxy proxy = new Proxy(proxyAdmin);
        proxyAddr = address(proxy);
        console.log("[2] Proxy                  :", proxyAddr);

        IOptimismPortal[] memory emptyPortals = new IOptimismPortal[](0);
        IProxyAdmin(proxyAdmin).upgradeAndCall(
            payable(proxyAddr),
            implAddr,
            abi.encodeCall(
                ComposeETHLockbox.initialize,
                (ISuperchainConfig(superchainConfig), emptyPortals)
            )
        );
        console.log("[3] upgradeAndCall(initialize) : ok");

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("  ComposeETHLockbox proxy :", proxyAddr);
        console.log("========================================");
    }
}
