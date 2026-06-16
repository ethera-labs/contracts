// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Proxy} from "@optimism/src/universal/Proxy.sol";
import {ProxyAdmin} from "@optimism/src/universal/ProxyAdmin.sol";
import {DisputeGameFactory} from "@optimism/src/dispute/DisputeGameFactory.sol";

contract DeployDisputeGameFactory is Script {
    function run(address admin) public returns (address dgfProxyAddr, address dgfImplAddr) {
        vm.startBroadcast();

        // 1) Deploy ProxyAdmin controlled by `admin`.
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin:", address(proxyAdmin));

        // 2) Deploy DisputeGameFactory behind Bedrock Proxy and initialize via ProxyAdmin (satisfies
        //    ProxyAdminOwnedBase checks in initialize()).
        DisputeGameFactory dgfImpl = new DisputeGameFactory();
        Proxy dgfProxy = new Proxy(address(proxyAdmin));
        bytes memory dgfInitData = abi.encodeWithSelector(DisputeGameFactory.initialize.selector, admin);

        proxyAdmin.upgradeAndCall(payable(address(dgfProxy)), address(dgfImpl), dgfInitData);
        DisputeGameFactory dgf = DisputeGameFactory(address(dgfProxy));
        console.log("DisputeGameFactory (proxy):", address(dgf));

        vm.stopBroadcast();

        return (address(dgfProxy), address(dgfImpl));
    }
}
