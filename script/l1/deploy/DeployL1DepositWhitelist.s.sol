// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Proxy} from "src/universal/Proxy.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {L1DepositWhitelist} from "src/l1/L1DepositWhitelist.sol";

/// @notice Deploys L1DepositWhitelist impl + proxy and initializes it.
///         Shared across all rollups on same L1.
///
/// Env:
///   PROXY_ADMIN          L1-level ProxyAdmin address
///   DEFAULT_ADMIN        Address that can grant/revoke roles
///   WHITELIST_ADMIN      Address that can update whitelist policy
contract DeployL1DepositWhitelist is Script {
    function run() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address whitelistAdmin = vm.envAddress("WHITELIST_ADMIN");

        console.log("========================================");
        console.log("Deploy L1DepositWhitelist");
        console.log("  proxyAdmin     :", proxyAdmin);
        console.log("  defaultAdmin   :", defaultAdmin);
        console.log("  whitelistAdmin :", whitelistAdmin);
        console.log("========================================");

        require(proxyAdmin != address(0), "PROXY_ADMIN not set");
        require(defaultAdmin != address(0), "DEFAULT_ADMIN not set");
        require(whitelistAdmin != address(0), "WHITELIST_ADMIN not set");

        vm.startBroadcast();

        L1DepositWhitelist impl = new L1DepositWhitelist();
        console.log("Impl deployed at:", address(impl));

        Proxy proxy = new Proxy(proxyAdmin);
        console.log("Proxy deployed at:", address(proxy));

        IProxyAdmin(proxyAdmin).upgradeAndCall(
            payable(address(proxy)),
            address(impl),
            abi.encodeCall(L1DepositWhitelist.initialize, (defaultAdmin, whitelistAdmin))
        );

        console.log("Proxy initialized");
        console.log("L1DepositWhitelist:", address(proxy));

        vm.stopBroadcast();
    }
}
