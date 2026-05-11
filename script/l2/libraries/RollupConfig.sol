// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";

/// @title RollupConfig
/// @notice Reads rollup configuration from config.json.
///         Reads rollup-specific config based on ROLLUP_NAME env var.
library RollupConfig {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string private constant CONFIG_JSON = "config.json";

    function rollupName() internal view returns (string memory) {
        return vm.envOr("ROLLUP_NAME", string(""));
    }

    /// @dev Uses bracket notation to support rollup names with hyphens (e.g. "chain-100003")
    function rollupKey(string memory key) internal view returns (string memory) {
        string memory rollup = rollupName();
        require(bytes(rollup).length > 0, "RollupConfig: ROLLUP_NAME not set");
        return string(abi.encodePacked('.rollups["', rollup, '"].', key));
    }

    function rollupL1Key(string memory key) internal view returns (string memory) {
        return rollupKey(string(abi.encodePacked("l1.", key)));
    }

    function jsonContent() internal view returns (string memory) {
        return vm.readFile(CONFIG_JSON);
    }

    // ============ L2 Rollup Configuration ============

    function chainId() internal view returns (uint256) {
        return vm.parseJsonUint(jsonContent(), rollupKey("chainId"));
    }

    function owner() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupKey("owner"));
        require(addr != address(0), "RollupConfig: owner not set in config.json");
        return addr;
    }

    function coordinator() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupKey("coordinator"));
        require(addr != address(0), "RollupConfig: coordinator not set in config.json");
        return addr;
    }

    function l1ChainId() internal view returns (uint256) {
        return vm.parseJsonUint(jsonContent(), rollupKey("l1ChainId"));
    }

    function l2Xdm() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupKey("l2Xdm"));
        require(addr != address(0), "RollupConfig: l2Xdm not set in config.json");
        return addr;
    }

    function create2Salt() internal view returns (bytes32) {
        return vm.parseJsonBytes32(jsonContent(), rollupKey("create2Salt"));
    }

    function initialEthSeed() internal view returns (uint256) {
        try vm.parseJsonUint(jsonContent(), rollupKey("initialEthSeed")) returns (uint256 seed) {
            return seed;
        } catch {
            return 0;
        }
    }

    // ============ L1 Rollup Migration Addresses ============

    function portalProxy() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupL1Key("portalProxy"));
        require(addr != address(0), "RollupConfig: l1.portalProxy not set in config.json");
        return addr;
    }

    function portalImpl() internal view returns (address) {
        return vm.parseJsonAddress(jsonContent(), rollupL1Key("portalImpl"));
    }

    function l1ProxyAdmin() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupL1Key("proxyAdmin"));
        require(addr != address(0), "RollupConfig: l1.proxyAdmin not set in config.json");
        return addr;
    }

    function l1ProxyAdminOwner() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupL1Key("proxyAdminOwner"));
        require(addr != address(0), "RollupConfig: l1.proxyAdminOwner not set in config.json");
        return addr;
    }

    function systemConfig() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), rollupL1Key("systemConfig"));
        require(addr != address(0), "RollupConfig: l1.systemConfig not set in config.json");
        return addr;
    }

    function l1CrossDomainMessenger() internal view returns (address) {
        return vm.parseJsonAddress(jsonContent(), rollupL1Key("l1CrossDomainMessenger"));
    }

    function l1StandardBridge() internal view returns (address) {
        return vm.parseJsonAddress(jsonContent(), rollupL1Key("l1StandardBridge"));
    }

    function l1ERC721Bridge() internal view returns (address) {
        return vm.parseJsonAddress(jsonContent(), rollupL1Key("l1ERC721Bridge"));
    }

    // ============ Validation ============

    function validateConfig() internal view {
        string memory rollup = rollupName();
        require(bytes(rollup).length > 0, "RollupConfig: ROLLUP_NAME not set");
        owner();
        l2Xdm();
        create2Salt();
    }
}
