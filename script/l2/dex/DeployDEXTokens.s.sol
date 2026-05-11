// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";
import {SSVMintable} from "src/l2/dex/SSVMintable.sol";
import {USDCMintable} from "src/l2/dex/USDCMintable.sol";

/// @title DeployDEXTokens
/// @notice Deployment script for SSV and USDC tokens on L2 networks.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   create2_salt   bytes32 salt for deterministic addresses
///
/// Env:
///   ROLLUP_NAME    selects section in rollups.toml (also used as output filename)
///   DEPLOYER_KEY   private key for broadcast
contract DeployDEXTokens is Script {
    using stdJson for string;

    function run() public returns (string memory finalJson) {
        bytes32 salt = RollupConfig.create2Salt();
        string memory networkName = RollupConfig.rollupName();

        console.log("========================================");
        console.log("Deploying DEX Tokens to:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deploy Salt:", vm.toString(salt));
        console.log("========================================");

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        address ssvAddr = _deployCreate2(salt, type(SSVMintable).creationCode);
        SSVMintable ssv = SSVMintable(ssvAddr);
        console.log("SSV Token deployed at:", address(ssv));

        address usdcAddr = _deployCreate2(salt, type(USDCMintable).creationCode);
        USDCMintable usdc = USDCMintable(usdcAddr);
        console.log("USDC Token deployed at:", address(usdc));

        vm.stopBroadcast();

        console.log("========================================");
        console.log("DEX Tokens Deployment Summary:");
        console.log("  SSV:   ", address(ssv));
        console.log("  USDC:  ", address(usdc));
        console.log("========================================");

        finalJson = _saveToJson(ssv, usdc);
        string memory filename = string.concat("artifacts/deploy-dex-tokens-", networkName, ".json");
        vm.writeJson(finalJson, filename);
        console.log("Deployment saved to:", filename);
    }

    function _saveToJson(SSVMintable ssv, USDCMintable usdc) internal returns (string memory) {
        string memory parent = "parent";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "SSV", address(ssv));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "USDC", address(usdc));

        string memory chain_info = "chainInfo";
        vm.serializeUint(chain_info, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", block.chainid);

        vm.serializeString(parent, deployed_addresses, deployed_addresses_output);
        return vm.serializeString(parent, chain_info, chain_info_output);
    }

    function _deployCreate2(bytes32 salt, bytes memory code) internal returns (address addr) {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }
}
