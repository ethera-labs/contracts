// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {WETH9} from "@external/WETH9.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";

/// @title DeployWETH
/// @notice Deployment script for WETH9 on L2 networks.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   create2_salt   bytes32 salt for deterministic address
///
/// Env:
///   ROLLUP_NAME    selects section in rollups.toml (also used as output filename)
///   DEPLOYER_KEY   private key for broadcast
contract DeployWETH is Script {
    using stdJson for string;

    function run() public returns (string memory finalJson) {
        bytes32 salt = RollupConfig.create2Salt();
        string memory networkName = RollupConfig.rollupName();

        console.log("========================================");
        console.log("Deploying WETH9 to:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deploy Salt:", vm.toString(salt));
        console.log("========================================");

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        address wethAddr = _deployCreate2(salt, type(WETH9).creationCode);
        WETH9 weth = WETH9(payable(wethAddr));

        vm.stopBroadcast();

        console.log("========================================");
        console.log("WETH9 Deployment Summary:");
        console.log("  WETH:", address(weth));
        console.log("  Name:", weth.name());
        console.log("  Symbol:", weth.symbol());
        console.log("========================================");

        finalJson = _saveToJson(weth);
        string memory filename = string.concat("artifacts/deploy-weth-", networkName, ".json");
        vm.writeJson(finalJson, filename);
        console.log("Deployment saved to:", filename);
    }

    function _saveToJson(WETH9 weth) internal returns (string memory) {
        string memory parent = "parent";

        string memory deployed_addresses = "addresses";
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "WETH", address(weth));

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
