// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { BaseDeployIO } from "script/deploy/BaseDeployIO.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IComposeAnchorStateRegistry } from "@ssv/src/interfaces/IComposeAnchorStateRegistry.sol";
import { IL1CrossDomainMessenger } from "interfaces/L1/IL1CrossDomainMessenger.sol";
import { IL1StandardBridge } from "interfaces/L1/IL1StandardBridge.sol";
import { IL1ERC721Bridge } from "interfaces/L1/IL1ERC721Bridge.sol";
import { ComposeETHLockbox } from "@ssv/src/ComposeETHLockbox.sol";

/// @title MigrateRollupInput
/// @notice Input configuration for Phase 2: Per-Rollup Migration
contract MigrateRollupInput is BaseDeployIO {
    // L2 Identity
    uint256 internal _l2ChainId;
    
    // Existing Rollup Contracts (to be upgraded)
    address internal _rollupProxyAdmin;
    address internal _rollupProxyAdminOwner;
    ISystemConfig internal _systemConfig;
    IOptimismPortal2 internal _optimismPortal;
    IL1CrossDomainMessenger internal _l1CrossDomainMessenger;
    IL1StandardBridge internal _l1StandardBridge;
    IL1ERC721Bridge internal _l1ERC721Bridge;
    
    // Phase 1 Shared Infrastructure (already deployed)
    address internal _composeProxyAdminOwner;
    ISuperchainConfig internal _composeSuperchainConfig;
    IDisputeGameFactory internal _composeDisputeGameFactory;
    IComposeAnchorStateRegistry internal _composeAnchorStateRegistry;
    ComposeETHLockbox internal _composeETHLockbox;
    
    // Migration Parameters
    uint256 internal _proofMaturityDelaySeconds;
    
    // Setters for L2 identity
    function set(bytes4 sel, uint256 val) public {
        if (sel == this.l2ChainId.selector) _l2ChainId = val;
        else if (sel == this.proofMaturityDelaySeconds.selector) _proofMaturityDelaySeconds = val;
        else revert("MigrateRollupInput: unknown uint256 selector");
    }
    
    // Setters for rollup contracts
    function set(bytes4 sel, address val) public {
        require(val != address(0), "MigrateRollupInput: zero address");
        
        if (sel == this.rollupProxyAdmin.selector) _rollupProxyAdmin = val;
        else if (sel == this.rollupProxyAdminOwner.selector) _rollupProxyAdminOwner = val;
        else if (sel == this.systemConfig.selector) _systemConfig = ISystemConfig(val);
        else if (sel == this.optimismPortal.selector) _optimismPortal = IOptimismPortal2(payable(val));
        else if (sel == this.l1CrossDomainMessenger.selector) _l1CrossDomainMessenger = IL1CrossDomainMessenger(val);
        else if (sel == this.l1StandardBridge.selector) _l1StandardBridge = IL1StandardBridge(payable(val));
        else if (sel == this.l1ERC721Bridge.selector) _l1ERC721Bridge = IL1ERC721Bridge(val);
        else if (sel == this.composeProxyAdminOwner.selector) _composeProxyAdminOwner = val;
        else if (sel == this.composeSuperchainConfig.selector) _composeSuperchainConfig = ISuperchainConfig(val);
        else if (sel == this.composeDisputeGameFactory.selector) _composeDisputeGameFactory = IDisputeGameFactory(val);
        else if (sel == this.composeAnchorStateRegistry.selector) _composeAnchorStateRegistry = IComposeAnchorStateRegistry(val);
        else if (sel == this.composeETHLockbox.selector) _composeETHLockbox = ComposeETHLockbox(payable(val));
        else revert("MigrateRollupInput: unknown address selector");
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
    
    function l1CrossDomainMessenger() public view returns (IL1CrossDomainMessenger) {
        require(address(_l1CrossDomainMessenger) != address(0), "l1CrossDomainMessenger not set");
        return _l1CrossDomainMessenger;
    }
    
    function l1StandardBridge() public view returns (IL1StandardBridge) {
        require(address(_l1StandardBridge) != address(0), "l1StandardBridge not set");
        return _l1StandardBridge;
    }
    
    function l1ERC721Bridge() public view returns (IL1ERC721Bridge) {
        require(address(_l1ERC721Bridge) != address(0), "l1ERC721Bridge not set");
        return _l1ERC721Bridge;
    }
    
    function composeProxyAdminOwner() public view returns (address) {
        require(_composeProxyAdminOwner != address(0), "composeProxyAdminOwner not set");
        return _composeProxyAdminOwner;
    }

    function composeSuperchainConfig() public view returns (ISuperchainConfig) {
        require(address(_composeSuperchainConfig) != address(0), "composeSuperchainConfig not set");
        return _composeSuperchainConfig;
    }
    
    function composeDisputeGameFactory() public view returns (IDisputeGameFactory) {
        require(address(_composeDisputeGameFactory) != address(0), "composeDisputeGameFactory not set");
        return _composeDisputeGameFactory;
    }
    
    function composeAnchorStateRegistry() public view returns (IComposeAnchorStateRegistry) {
        require(address(_composeAnchorStateRegistry) != address(0), "composeAnchorStateRegistry not set");
        return _composeAnchorStateRegistry;
    }
    
    function composeETHLockbox() public view returns (ComposeETHLockbox) {
        require(address(_composeETHLockbox) != address(0), "composeETHLockbox not set");
        return _composeETHLockbox;
    }
    
    function proofMaturityDelaySeconds() public view returns (uint256) {
        require(_proofMaturityDelaySeconds > 0, "proofMaturityDelaySeconds not set");
        return _proofMaturityDelaySeconds;
    }
}

/// @title MigrateRollupOutput
/// @notice Output containing all newly deployed implementation addresses
contract MigrateRollupOutput is BaseDeployIO {
    address internal _systemConfigImpl;
    address internal _optimismPortalImpl;
    address internal _l1CrossDomainMessengerImpl;
    address internal _l1StandardBridgeImpl;
    address internal _l1ERC721BridgeImpl;
    
    // Setters
    function set(bytes4 sel, address val) public {
        require(val != address(0), "MigrateRollupOutput: zero address");
        
        if (sel == this.systemConfigImpl.selector) _systemConfigImpl = val;
        else if (sel == this.optimismPortalImpl.selector) _optimismPortalImpl = val;
        else if (sel == this.l1CrossDomainMessengerImpl.selector) _l1CrossDomainMessengerImpl = val;
        else if (sel == this.l1StandardBridgeImpl.selector) _l1StandardBridgeImpl = val;
        else if (sel == this.l1ERC721BridgeImpl.selector) _l1ERC721BridgeImpl = val;
        else revert("MigrateRollupOutput: unknown selector");
    }
    
    // Getters
    function systemConfigImpl() public view returns (address) {
        require(_systemConfigImpl != address(0), "systemConfigImpl not set");
        return _systemConfigImpl;
    }
    
    function optimismPortalImpl() public view returns (address) {
        require(_optimismPortalImpl != address(0), "optimismPortalImpl not set");
        return _optimismPortalImpl;
    }
    
    function l1CrossDomainMessengerImpl() public view returns (address) {
        require(_l1CrossDomainMessengerImpl != address(0), "l1CrossDomainMessengerImpl not set");
        return _l1CrossDomainMessengerImpl;
    }
    
    function l1StandardBridgeImpl() public view returns (address) {
        require(_l1StandardBridgeImpl != address(0), "l1StandardBridgeImpl not set");
        return _l1StandardBridgeImpl;
    }
    
    function l1ERC721BridgeImpl() public view returns (address) {
        require(_l1ERC721BridgeImpl != address(0), "l1ERC721BridgeImpl not set");
        return _l1ERC721BridgeImpl;
    }
}
