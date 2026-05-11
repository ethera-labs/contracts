// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { BaseDeployIO } from "script/l1/deploy/BaseDeployIO.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IComposeAnchorStateRegistry } from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";
import { ComposeETHLockbox } from "src/l1/ComposeETHLockbox.sol";

/// @title MigrateRollupV4Input
/// @notice Input configuration for Phase 2: V4 Rollup Migration to Compose
/// @dev Simplified input for V4 rollups that are already upgraded to OP Stack v4/v5
contract MigrateRollupV4Input is BaseDeployIO {
    // L2 Identity
    uint256 internal _l2ChainId;
    
    // Existing V4 Rollup Contracts
    address internal _rollupProxyAdmin;
    address internal _rollupProxyAdminOwner;
    ISystemConfig internal _systemConfig;
    IOptimismPortal2 internal _optimismPortal;
    
    // Phase 1 Shared Infrastructure (already deployed)
    address internal _composeProxyAdminOwner;
    ISuperchainConfig internal _composeSuperchainConfig;
    IComposeAnchorStateRegistry internal _composeAnchorStateRegistry;
    ComposeETHLockbox internal _composeETHLockbox;
    
    // Setters for L2 identity
    function set(bytes4 sel, uint256 val) public {
        if (sel == this.l2ChainId.selector) _l2ChainId = val;
        else revert("MigrateRollupV4Input: unknown uint256 selector");
    }
    
    // Setters for addresses
    function set(bytes4 sel, address val) public {
        require(val != address(0), "MigrateRollupV4Input: zero address");
        
        if (sel == this.rollupProxyAdmin.selector) _rollupProxyAdmin = val;
        else if (sel == this.rollupProxyAdminOwner.selector) _rollupProxyAdminOwner = val;
        else if (sel == this.systemConfig.selector) _systemConfig = ISystemConfig(val);
        else if (sel == this.optimismPortal.selector) _optimismPortal = IOptimismPortal2(payable(val));
        else if (sel == this.composeProxyAdminOwner.selector) _composeProxyAdminOwner = val;
        else if (sel == this.composeSuperchainConfig.selector) _composeSuperchainConfig = ISuperchainConfig(val);
        else if (sel == this.composeAnchorStateRegistry.selector) _composeAnchorStateRegistry = IComposeAnchorStateRegistry(val);
        else if (sel == this.composeETHLockbox.selector) _composeETHLockbox = ComposeETHLockbox(payable(val));
        else revert("MigrateRollupV4Input: unknown address selector");
    }
    
    // Getters
    function l2ChainId() public view returns (uint256) {
        require(_l2ChainId != 0, "l2ChainId not set");
        return _l2ChainId;
    }
    
    function rollupProxyAdmin() public view returns (address) {
        require(_rollupProxyAdmin != address(0), "rollupProxyAdmin not set");
        return _rollupProxyAdmin;
    }
    
    function rollupProxyAdminOwner() public view returns (address) {
        require(_rollupProxyAdminOwner != address(0), "rollupProxyAdminOwner not set");
        return _rollupProxyAdminOwner;
    }
    
    function systemConfig() public view returns (ISystemConfig) {
        require(address(_systemConfig) != address(0), "systemConfig not set");
        return _systemConfig;
    }
    
    function optimismPortal() public view returns (IOptimismPortal2) {
        require(address(_optimismPortal) != address(0), "optimismPortal not set");
        return _optimismPortal;
    }
    
    function composeProxyAdminOwner() public view returns (address) {
        require(_composeProxyAdminOwner != address(0), "composeProxyAdminOwner not set");
        return _composeProxyAdminOwner;
    }

    function composeSuperchainConfig() public view returns (ISuperchainConfig) {
        require(address(_composeSuperchainConfig) != address(0), "composeSuperchainConfig not set");
        return _composeSuperchainConfig;
    }
    
    function composeAnchorStateRegistry() public view returns (IComposeAnchorStateRegistry) {
        require(address(_composeAnchorStateRegistry) != address(0), "composeAnchorStateRegistry not set");
        return _composeAnchorStateRegistry;
    }
    
    function composeETHLockbox() public view returns (ComposeETHLockbox) {
        require(address(_composeETHLockbox) != address(0), "composeETHLockbox not set");
        return _composeETHLockbox;
    }
}
