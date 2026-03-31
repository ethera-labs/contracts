// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { ComposeERC20Lockbox } from "src/ComposeERC20Lockbox.sol";

contract DeployERC20LockboxProxy is Script {
    function run() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address lockboxImpl = vm.envAddress("LOCKBOX_IMPL");
        address superchainConfig = vm.envAddress("SUPERCHAIN_CONFIG");
        address bridge = vm.envAddress("BRIDGE");

        address[] memory bridges = new address[](1);
        bridges[0] = bridge;

        vm.startBroadcast();

        Proxy proxy = new Proxy(proxyAdmin);
        console.log("Lockbox proxy deployed at:", address(proxy));

        IProxyAdmin(proxyAdmin).upgradeAndCall(
            payable(address(proxy)),
            lockboxImpl,
            abi.encodeCall(ComposeERC20Lockbox.initialize, (ISuperchainConfig(superchainConfig), bridges))
        );
        console.log("Lockbox initialized with bridge:", bridge);

        vm.stopBroadcast();
    }
}
