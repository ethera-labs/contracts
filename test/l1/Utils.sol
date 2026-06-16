// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {DisputeGameFactory} from "@optimism/src/dispute/DisputeGameFactory.sol";
import {Proxy} from "@optimism/src/universal/Proxy.sol";
import {ProxyAdmin} from "@optimism/src/universal/ProxyAdmin.sol";

contract Utils is Test {
    function deployDisputeGameFactory() public returns (DisputeGameFactory) {
        ProxyAdmin proxyAdmin = new ProxyAdmin(address(this));
        DisputeGameFactory factoryImpl = new DisputeGameFactory();
        Proxy factoryProxy = new Proxy(address(proxyAdmin));
        proxyAdmin.upgradeAndCall(payable(address(factoryProxy)), address(factoryImpl), abi.encodeCall(DisputeGameFactory.initialize, (address(this))));
        return DisputeGameFactory(address(factoryProxy));
    }
}
