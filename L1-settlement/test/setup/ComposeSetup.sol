// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

import { ComposeDeployUtils } from "script/libraries/ComposeDeployUtils.sol";
import { ComposeConfig } from "script/libraries/ComposeConfig.sol";
import { DeploySharedInfra, DeploySharedInfraOutput } from "script/deploy/DeploySharedInfra.s.sol";

// Interfaces
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IComposeAnchorStateRegistry } from "src/interfaces/IComposeAnchorStateRegistry.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

// Contracts
import { ComposeAnchorStateRegistry } from "src/ComposeAnchorStateRegistry.sol";
import { ComposeDisputeGame } from "src/ComposeDisputeGame.sol";
import { ComposeETHLockbox } from "src/ComposeETHLockbox.sol";
import { MockVerifier } from "test/mock/MockVerifier.sol";
import { MockSuperchainConfig } from "test/mock/MockSuperchainConfig.sol";

/// @title ComposeSetup
/// @notice Base test setup for Compose tests. Uses vm.etch pattern to avoid bytecode bloat.
///         All test contracts should inherit from this to get access to deployed Compose infrastructure.
abstract contract ComposeSetup is Test {
    // Deterministic address for deployment script (using keccak256)
    DeploySharedInfra internal constant deploySharedInfra = 
        DeploySharedInfra(address(uint160(uint256(keccak256("compose.deploy.shared")))));
    
    // Deployed contracts - populated during setUp
    IProxyAdmin internal composeProxyAdmin;
    ISuperchainConfig internal composeSuperchainConfig;
    ISuperchainConfig internal rollupSuperchainConfig;
    IDisputeGameFactory internal composeDisputeGameFactory;
    IComposeAnchorStateRegistry internal composeAnchorStateRegistry;
    ComposeETHLockbox internal composeETHLockbox;
    ComposeDisputeGame internal composeDisputeGameImpl;
    MockVerifier internal mockSP1Verifier;
    
    // Test actors
    address internal guardian;
    address internal proxyAdminOwner;
    address internal authorizedProposer;
    address internal alice;
    address internal bob;
    
    /// @notice Indicates whether this is a fork test
    function isForkTest() public view returns (bool) {
        return vm.envOr("FORK_TEST", false);
    }
    
    /// @notice Main setup function - deploys Compose shared infrastructure
    function setUp() public virtual {
        console.log("ComposeSetup: Starting setup...");
        
        // Deploy MockVerifier - use dedicated address for sp1Verifier
        mockSP1Verifier = new MockVerifier();
        mockSP1Verifier.mockVerifyProof(true); // Accept all proofs in tests
        
        // Override sp1_verifier address in networks.toml to point to MockVerifier
        // Note: Address 0x1804... is used for guardian/owner roles, actual verifier is separate
        vm.etch(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38), address(mockSP1Verifier).code);
        
        // Fund the deployer address used in networks.toml (same for all roles in tests)
        vm.deal(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38), 1000 ether);
        
        // Setup test actors - use addresses from deployed infrastructure
        guardian = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38); // Same as TOML config
        proxyAdminOwner = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38); // Same as TOML config
        authorizedProposer = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38); // Same as TOML config
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        
        // Fork test setup (optional for integration tests)
        if (isForkTest()) {
            string memory rpcUrl = vm.envString("FORK_RPC_URL");
            uint256 blockNumber = vm.envOr("FORK_BLOCK_NUMBER", uint256(0));
            
            if (blockNumber > 0) {
                vm.createSelectFork(rpcUrl, blockNumber);
            } else {
                vm.createSelectFork(rpcUrl);
            }
            console.log("ComposeSetup: Fork selected");
            console.log("  Chain ID:", block.chainid);
            console.log("  Block number:", block.number);
        }
        
        // Etch the deployment script at deterministic address
        // This avoids including deployment script bytecode in test contract
        ComposeDeployUtils.etchLabelAndAllowCheatcodes(
            address(deploySharedInfra),
            "DeploySharedInfra.s.sol:DeploySharedInfra"
        );
        
        console.log("ComposeSetup: Deploying shared infrastructure...");
        
        // Deploy shared infrastructure using the script
        DeploySharedInfraOutput output = deploySharedInfra.run();
        
        // Store deployed contract references
        composeProxyAdmin = output.composeProxyAdmin();
        composeSuperchainConfig = output.composeSuperchainConfigProxy();
        composeDisputeGameFactory = output.composeDisputeGameFactoryProxy();
        composeAnchorStateRegistry = output.composeAnchorStateRegistryProxy();
        composeETHLockbox = output.composeETHLockboxProxy();
        composeDisputeGameImpl = output.composeDisputeGameImpl();

        // Different superchain config
        rollupSuperchainConfig = ISuperchainConfig(address(new MockSuperchainConfig()));

        // Get mock verifier from deployment (sp1_verifier in test deployment)
        mockSP1Verifier = MockVerifier(address(composeDisputeGameImpl.PROOF_VERIFIER()));
        
        console.log("ComposeSetup: Setup complete!");
        console.log("  SuperchainConfig:", address(composeSuperchainConfig));
        console.log("  DisputeGameFactory:", address(composeDisputeGameFactory));
        console.log("  AnchorStateRegistry:", address(composeAnchorStateRegistry));
        console.log("  ETHLockbox:", address(composeETHLockbox));
        console.log("  DisputeGame impl:", address(composeDisputeGameImpl));
    }
    
    /// @notice Helper to get test config for deployment
    function _getTestDeployConfig() internal pure returns (DeploySharedInfra) {
        // Override with test values if needed
        return deploySharedInfra;
    }
}
