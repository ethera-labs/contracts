// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {SP1MockVerifier} from "src/l1/mock/SP1MockVerifier.sol";

contract DeploySP1MockVerifier is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        SP1MockVerifier verifier = new SP1MockVerifier();
        console.log("SP1MockVerifier deployed:", address(verifier));

        vm.stopBroadcast();
    }
}
