// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IComposeL2OutputOracleTypes} from "src/l1/interfaces/IComposeL2OutputOracle.sol";
import {ComposeL2OutputOracle} from "src/l1/ComposeL2OutputOracle.sol";

contract DeployComposeL2OutputOracle is Script {
    function run(
        address verifier,
        address owner,
        address proposer,
        bytes32 aggregationVkey,
        uint256 startingSuperBlockNumber
    ) public returns (address proxyAddress) {
        vm.startBroadcast();

        console.log("Deploying ComposeL2OutputOracle implementation...");
        address composeL2OutputOracleImpl = address(
            new ComposeL2OutputOracle()
        );
        console.log(
            "ComposeL2OutputOracle implementation deployed at:",
            composeL2OutputOracleImpl
        );

        bytes memory initData = abi.encodeWithSelector(
            ComposeL2OutputOracle.initialize.selector,
            IComposeL2OutputOracleTypes.InitParams({
                startingSuperBlockNumber: startingSuperBlockNumber,
                aggregationVkey: aggregationVkey,
                verifier: verifier,
                owner: owner,
                proposer: proposer
            })
        );

        console.log("Deploying ComposeL2OutputOracle Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            composeL2OutputOracleImpl,
            initData
        );
        proxyAddress = address(proxy);

        console.log("ComposeL2OutputOracle proxy deployed at:", proxyAddress);

        vm.stopBroadcast();
    }
}
