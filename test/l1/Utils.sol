// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ComposeL2OutputOracle} from "src/l1/ComposeL2OutputOracle.sol";
import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {DisputeGameFactory} from "@optimism/src/dispute/DisputeGameFactory.sol";
import {Proxy} from "@optimism/src/universal/Proxy.sol";
import {ProxyAdmin} from "@optimism/src/universal/ProxyAdmin.sol";

contract Utils is Test {
    function deployL2OutputOracle(ComposeL2OutputOracle.InitParams memory initParams)
    public
    returns (ComposeL2OutputOracle)
    {
        bytes memory initializationParams =
                            abi.encodeWithSelector(ComposeL2OutputOracle.initialize.selector, initParams);

        Proxy l2OutputOracleProxy = new Proxy(address(this));
        l2OutputOracleProxy.upgradeToAndCall(address(new ComposeL2OutputOracle()), initializationParams);

        return ComposeL2OutputOracle(address(l2OutputOracleProxy));
    }

    function deployDisputeGameFactory() public returns (DisputeGameFactory) {
        ProxyAdmin proxyAdmin = new ProxyAdmin(address(this));
        DisputeGameFactory factoryImpl = new DisputeGameFactory();
        Proxy factoryProxy = new Proxy(address(proxyAdmin));
        proxyAdmin.upgradeAndCall(
            payable(address(factoryProxy)),
            address(factoryImpl),
            abi.encodeCall(DisputeGameFactory.initialize, (address(this)))
        );
        return DisputeGameFactory(address(factoryProxy));
    }
}