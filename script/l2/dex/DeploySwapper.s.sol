// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";
import {USDC_SSV_WETH_Swapper} from "src/l2/dex/USDC_SSV_WETH_Swapper.sol";

/// @title DeploySwapper
/// @notice Deployment script for USDC_SSV_WETH_Swapper on L2 networks.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   create2_salt   bytes32 salt for deterministic address
///
/// Env:
///   ROLLUP_NAME    selects section in rollups.toml (also used as output filename)
///   DEPLOYER_KEY   private key for broadcast
///   WETH_ADDRESS   deployed WETH9 address on this L2
///   USDC_ADDRESS   deployed USDCMintable address on this L2
///   SSV_ADDRESS    deployed SSVMintable address on this L2
contract DeploySwapper is Script {
    using stdJson for string;

    function run() public returns (string memory finalJson) {
        bytes32 salt = RollupConfig.create2Salt();
        string memory networkName = RollupConfig.rollupName();
        address weth = vm.envAddress("WETH_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address ssv = vm.envAddress("SSV_ADDRESS");

        console.log("========================================");
        console.log("Deploying USDC_SSV_WETH_Swapper to:", networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deploy Salt:", vm.toString(salt));
        console.log("========================================");
        console.log("Token Addresses:");
        console.log("  WETH:", weth);
        console.log("  USDC:", usdc);
        console.log("  SSV: ", ssv);
        console.log("========================================");

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        address swapperAddr = _deployCreate2(salt, abi.encodePacked(type(USDC_SSV_WETH_Swapper).creationCode, abi.encode(weth, usdc, ssv)));
        USDC_SSV_WETH_Swapper swapper = USDC_SSV_WETH_Swapper(swapperAddr);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Swapper Deployment Summary:");
        console.log("  Swapper:", address(swapper));
        console.log("  WETH:   ", swapper.weth());
        console.log("  USDC:   ", swapper.usdc());
        console.log("  SSV:    ", swapper.ssv());
        console.log("========================================");

        finalJson = _saveToJson(swapper, weth, usdc, ssv);
        string memory filename = string.concat("artifacts/deploy-swapper-", networkName, ".json");
        vm.writeJson(finalJson, filename);
        console.log("Deployment saved to:", filename);
    }

    function _saveToJson(USDC_SSV_WETH_Swapper swapper, address weth, address usdc, address ssv)
        internal
        returns (string memory)
    {
        string memory parent = "parent";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "Swapper", address(swapper));
        vm.serializeAddress(deployed_addresses, "WETH", weth);
        vm.serializeAddress(deployed_addresses, "USDC", usdc);
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "SSV", ssv);

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
