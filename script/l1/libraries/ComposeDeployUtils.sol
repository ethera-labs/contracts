// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @title ComposeDeployUtils
/// @notice Utilities for deploying contracts with CREATE and CREATE2.
///         Provides automatic validation, labeling, and artifact management.
library ComposeDeployUtils {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Default salt for CREATE2 deployments
    bytes32 internal constant DEFAULT_SALT = keccak256("compose-settlement-v1");

    /// @notice Deploys a contract via CREATE
    /// @param _name Contract name (e.g., "SuperchainConfig")
    /// @param _args ABI-encoded constructor arguments
    /// @return addr_ Deployed contract address
    function create1(string memory _name, bytes memory _args) internal returns (address payable addr_) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(_name), _args);
        assembly {
            addr_ := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        assertValidContractAddress(addr_);
    }

    /// @notice Deploys a contract via CREATE2
    /// @param _name Contract name
    /// @param _args ABI-encoded constructor arguments
    /// @param _salt Salt for deterministic address
    /// @return addr_ Deployed contract address
    function create2(string memory _name, bytes memory _args, bytes32 _salt) internal returns (address payable addr_) {
        bytes memory initCode = abi.encodePacked(vm.getCode(_name), _args);
        address preComputedAddress = vm.computeCreate2Address(_salt, keccak256(initCode));
        require(preComputedAddress.code.length == 0, "ComposeDeployUtils: contract already deployed");

        assembly {
            addr_ := create2(0, add(initCode, 0x20), mload(initCode), _salt)
            if iszero(addr_) {
                let size := returndatasize()
                returndatacopy(0, 0, size)
                revert(0, size)
            }
        }
        assertValidContractAddress(addr_);
    }

    /// @notice Deploys a contract deterministically using DEFAULT_SALT
    /// @param _name Contract name
    /// @param _args ABI-encoded constructor arguments
    /// @return addr_ Deployed contract address
    function createDeterministic(string memory _name, bytes memory _args) internal returns (address payable addr_) {
        return create2(_name, _args, DEFAULT_SALT);
    }

    /// @notice Encodes constructor arguments
    /// @param _args Raw constructor call data
    /// @return Encoded constructor arguments (strips function selector)
    function encodeConstructor(bytes memory _args) internal pure returns (bytes memory) {
        if (_args.length < 4) return _args;
        // Strip the 4-byte function selector
        bytes memory encoded = new bytes(_args.length - 4);
        for (uint256 i = 0; i < encoded.length; i++) {
            encoded[i] = _args[i + 4];
        }
        return encoded;
    }

    /// @notice Validates that an address contains contract code
    /// @param _addr Address to validate
    function assertValidContractAddress(address _addr) internal view {
        require(_addr != address(0), "ComposeDeployUtils: zero address");
        require(_addr.code.length > 0, "ComposeDeployUtils: no code at address");
    }

    /// @notice Etches contract bytecode at a specific address and allows cheatcodes
    /// @param _etchTo Address to etch the contract at
    /// @param _cname Contract name (e.g., "DeploySharedInfra.s.sol:DeploySharedInfra")
    function etchLabelAndAllowCheatcodes(address _etchTo, string memory _cname) internal {
        vm.etch(_etchTo, vm.getDeployedCode(_cname));
        vm.allowCheatcodes(_etchTo);

        // Extract label from contract name (after the colon)
        bytes memory cnameBytes = bytes(_cname);
        uint256 colonIndex = 0;
        for (uint256 i = cnameBytes.length; i > 0; i--) {
            if (cnameBytes[i - 1] == ":") {
                colonIndex = i;
                break;
            }
        }

        string memory contractLabel;
        if (colonIndex > 0 && colonIndex < cnameBytes.length) {
            bytes memory labelBytes = new bytes(cnameBytes.length - colonIndex);
            for (uint256 i = 0; i < labelBytes.length; i++) {
                labelBytes[i] = cnameBytes[colonIndex + i];
            }
            contractLabel = string(labelBytes);
        } else {
            contractLabel = _cname;
        }

        vm.label(_etchTo, contractLabel);
    }

    /// @notice Labels an address with a descriptive name
    /// @param _addr Address to label
    /// @param _label Label string
    function label(address _addr, string memory _label) internal {
        vm.label(_addr, _label);
    }
}
