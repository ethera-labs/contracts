// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { UniversalBridgeMailbox } from "@ssv/src/bridge/UniversalBridgeMailbox.sol";
import { CetFactory } from "@ssv/src/bridge/CetFactory.sol";
import { UniversalBridge } from "@ssv/src/bridge/UniversalBridge.sol";

contract DeployUniversalBridge is Script {
    using stdJson for string;

    function run(address coordinator, address ethLiquidity, string memory networkName)
    public
    returns (string memory finalJson)
    {
        bytes32 salt = vm.envBytes32("DEPLOY_SALT");

        console.log("========================================");
        console.log("Deploying Bridge System");
        console.log("Network:", networkName);
        console.log("Coordinator:", coordinator);
        console.log("Chain ID:", block.chainid);
        console.log("Salt:", vm.toString(salt));
        console.log("========================================");

        vm.startBroadcast();

        address mailboxAddr = _deployCreate2(
            salt,
            abi.encodePacked(type(UniversalBridgeMailbox).creationCode, abi.encode(coordinator))
        );
        console.log("Mailbox deployed at:", mailboxAddr);

        address cetFactoryAddr = _deployCreate2(
            salt,
            abi.encodePacked(type(CetFactory).creationCode)
        );
        console.log("CetFactory deployed at:", cetFactoryAddr);

        bytes memory bridgeCreationCode = abi.encodePacked(
            type(UniversalBridge).creationCode,
            abi.encode(mailboxAddr, cetFactoryAddr, ethLiquidity)
        );
        address predictedBridgeAddr = _predictCreate2(salt, bridgeCreationCode);
        console.log("Predicted UniversalBridge address:", predictedBridgeAddr);

        address bridgeAddr = _deployCreate2(salt, bridgeCreationCode);
        require(bridgeAddr == predictedBridgeAddr, "Bridge address mismatch");
        console.log("UniversalBridge deployed at:", bridgeAddr);

        UniversalBridgeMailbox(mailboxAddr).setBridge(bridgeAddr);
        console.log("Mailbox bridge set to:", bridgeAddr);

        CetFactory(cetFactoryAddr).setBridge(bridgeAddr);
        console.log("CetFactory bridge set to:", bridgeAddr);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Deployment Summary:");
        console.log("  Mailbox:        ", mailboxAddr);
        console.log("  CetFactory:     ", cetFactoryAddr);
        console.log("  UniversalBridge:", bridgeAddr);
        console.log("  Coordinator:    ", coordinator);
        console.log("========================================");

        finalJson = _saveToJson(coordinator, mailboxAddr, cetFactoryAddr, bridgeAddr);

        string memory filename = string.concat("artifacts/deploy-", networkName, ".json");
        vm.writeJson(finalJson, filename);
        console.log("Deployment saved to:", filename);
        return finalJson;
    }

    function _deployCreate2(bytes32 salt, bytes memory code) internal returns (address addr){
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }

    function _predictCreate2(bytes32 salt, bytes memory code) internal view returns (address) {
        bytes32 codeHash = keccak256(code);
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)
                    )
                )
            )
        );
    }

    function _saveToJson(
        address coordinator,
        address mailbox,
        address cetFactory,
        address bridge
    ) internal returns (string memory) {
        string memory parent = "parent";

        string memory deployed = "addresses";
        vm.serializeAddress(deployed, "Mailbox", mailbox);
        vm.serializeAddress(deployed, "CetFactory", cetFactory);
        vm.serializeAddress(deployed, "UniversalBridge", bridge);
        string memory deployedOutput =
                            vm.serializeAddress(deployed, "Coordinator", coordinator);

        string memory chainInfo = "chainInfo";
        vm.serializeUint(chainInfo, "chainId", block.chainid);
        string memory chainOutput =
                            vm.serializeUint(chainInfo, "deploymentBlock", block.number);

        vm.serializeString(parent, deployed, deployedOutput);
        return vm.serializeString(parent, chainInfo, chainOutput);
    }
}