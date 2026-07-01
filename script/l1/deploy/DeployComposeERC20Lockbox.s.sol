// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {ComposeERC20Lockbox} from "src/l1/ComposeERC20Lockbox.sol";

contract DeployComposeERC20Lockbox is Script {
    function run() public returns (address) {
        vm.startBroadcast();
        ComposeERC20Lockbox impl = new ComposeERC20Lockbox();
        vm.stopBroadcast();

        console.log("ComposeERC20Lockbox impl deployed at:", address(impl));
        return address(impl);
    }
}
