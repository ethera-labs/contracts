// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ComposeL1StandardBridge } from "src/ComposeL1StandardBridge.sol";

contract DeployComposeL1StandardBridge is Script {
    function run() public returns (address) {
        vm.startBroadcast();
        ComposeL1StandardBridge impl = new ComposeL1StandardBridge();
        vm.stopBroadcast();

        console.log("ComposeL1StandardBridge impl deployed at:", address(impl));
        return address(impl);
    }
}
