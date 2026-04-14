// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Mailbox } from "@ssv/src/core/Mailbox.sol";
import { PingPong } from "@ssv/src/core/PingPong.sol";
import { BridgeableToken } from "@ssv/src/core/BridgeableToken.sol";
import { Bridge } from "@ssv/src/core/Bridge.sol";

/**
 * @title DeployContracts
 * @notice Unified deployment script for all rollup networks
 * @dev Deploys all contracts using CREATE2 for deterministic addresses
 */
contract DeployContracts is Script {
    using stdJson for string;

    /**
     * @notice Main deployment function
     * @param coordinator Address of the coordinator for cross-rollup messages
     * @param networkName Name of the network (for output filename)
     * @return finalJson JSON string with deployment information
     */
    function run(address coordinator, string memory networkName) 
        public 
        returns (string memory finalJson) 
    {
        bytes32 salt = vm.envBytes32("DEPLOY_SALT");

        console.log("========================================");
        console.log("Deploying to:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Coordinator:", coordinator);
        console.log("Deploy Salt:", vm.toString(salt));
        console.log("========================================");

        vm.startBroadcast();

        // Deploy Mailbox
        address mailboxAddr = _deployCreate2(
            salt,
            abi.encodePacked(
                type(Mailbox).creationCode,
                abi.encode(coordinator)
            )
        );
        Mailbox mailbox = Mailbox(mailboxAddr);
        console.log("Mailbox deployed at:", address(mailbox));

        // Deploy PingPong
        address pingPongAddr = _deployCreate2(
            salt,
            abi.encodePacked(
                type(PingPong).creationCode,
                abi.encode(address(mailbox))
            )
        );
        PingPong pingPong = PingPong(pingPongAddr);
        console.log("PingPong deployed at:", address(pingPong));

        // Deploy Bridge
        address bridgeAddr = _deployCreate2(
            salt,
            abi.encodePacked(
                type(Bridge).creationCode,
                abi.encode(address(mailbox))
            )
        );
        Bridge bridge = Bridge(bridgeAddr);
        console.log("Bridge deployed at:", address(bridge));

        // Deploy BridgeableToken
        address tokenAddr = _deployCreate2(
            salt,
            abi.encodePacked(
                type(BridgeableToken).creationCode,
                abi.encode(address(bridge))
            )
        );
        BridgeableToken token = BridgeableToken(tokenAddr);
        console.log("BridgeableToken deployed at:", address(token));

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Deployment Summary:");
        console.log("  Mailbox:          ", address(mailbox));
        console.log("  PingPong:         ", address(pingPong));
        console.log("  Bridge:           ", address(bridge));
        console.log("  BridgeableToken:  ", address(token));
        console.log("  Coordinator:      ", coordinator);
        console.log("========================================");

        // Save deployment info to JSON
        finalJson = _saveToJson(coordinator, bridge, pingPong, mailbox, token);
        
        // Write to artifacts directory with network name
        string memory filename = string.concat("artifacts/deploy-", networkName, ".json");
        vm.writeJson(finalJson, filename);
        
        console.log("Deployment saved to:", filename);
        
        return finalJson;
    }

    /**
     * @notice Create JSON output with deployment information
     */
    function _saveToJson(
        address coordinator,
        Bridge bridge,
        PingPong pingPong,
        Mailbox mailbox,
        BridgeableToken token
    ) internal returns (string memory) {
        string memory parent = "parent";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "Mailbox", address(mailbox));
        vm.serializeAddress(deployed_addresses, "PingPong", address(pingPong));
        vm.serializeAddress(deployed_addresses, "BridgeableToken", address(token));
        vm.serializeAddress(deployed_addresses, "Bridge", address(bridge));

        string memory deployed_addresses_output = vm.serializeAddress(
            deployed_addresses,
            "Coordinator",
            coordinator
        );

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(
            chain_info,
            "chainId",
            block.chainid
        );

        vm.serializeString(
            parent,
            deployed_addresses,
            deployed_addresses_output
        );
        return vm.serializeString(parent, chain_info, chain_info_output);
    }

    /**
     * @notice Deploy contract using CREATE2 for deterministic addresses
     * @param salt Salt for CREATE2
     * @param code Contract bytecode (with constructor args if any)
     * @return addr Deployed contract address
     */
    function _deployCreate2(bytes32 salt, bytes memory code) 
        internal 
        returns (address addr) 
    {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }
}
