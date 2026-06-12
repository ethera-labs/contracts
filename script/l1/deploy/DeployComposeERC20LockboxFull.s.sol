// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Proxy} from "src/universal/Proxy.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {ComposeERC20Lockbox} from "src/l1/ComposeERC20Lockbox.sol";
import {ISuperchainConfig} from "interfaces/L1/ISuperchainConfig.sol";
import {IComposePortal} from "src/l1/interfaces/IComposePortal.sol";

/// @title DeployComposeERC20LockboxFull
/// @notice Deploy ComposeERC20Lockbox impl + proxy + initialize with an empty
///         portal list. Portals get authorized later per rollup via UpgradeToComposeBridge.
///
/// Env:
///   PROXY_ADMIN          existing ComposeProxyAdmin
///   PROXY_ADMIN_OWNER    owner of ProxyAdmin (signs upgradeAndCall)
///   SUPERCHAIN_CONFIG    existing SuperchainConfig proxy
contract DeployComposeERC20LockboxFull is Script {
    function run() external returns (address proxyAddr, address implAddr) {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        address superchainConfig = vm.envAddress("SUPERCHAIN_CONFIG");

        vm.startBroadcast(proxyAdminOwner);

        ComposeERC20Lockbox impl = new ComposeERC20Lockbox();
        implAddr = address(impl);
        console.log("\n[1] ComposeERC20Lockbox impl :", implAddr);

        Proxy proxy = new Proxy(proxyAdmin);
        proxyAddr = address(proxy);
        console.log("[2] Proxy                    :", proxyAddr);

        IComposePortal[] memory emptyPortals = new IComposePortal[](0);
        IProxyAdmin(proxyAdmin)
            .upgradeAndCall(payable(proxyAddr), implAddr, abi.encodeCall(ComposeERC20Lockbox.initialize, (ISuperchainConfig(superchainConfig), emptyPortals)));
        console.log("[3] upgradeAndCall(initialize) : ok");

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("  ComposeERC20Lockbox proxy :", proxyAddr);
        console.log("========================================");
    }
}
