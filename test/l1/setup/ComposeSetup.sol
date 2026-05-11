// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { console2 as console } from "forge-std/console2.sol";

import { ComposeDeployUtils } from "script/l1/libraries/ComposeDeployUtils.sol";
import { DeploySharedInfra, DeploySharedInfraInput, DeploySharedInfraOutput } from "script/l1/deploy/DeploySharedInfra.s.sol";

// Interfaces
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IDisputeGameFactory } from "interfaces/dispute/IDisputeGameFactory.sol";
import { IComposeAnchorStateRegistry } from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

// Contracts
import { ComposeAnchorStateRegistry } from "src/l1/ComposeAnchorStateRegistry.sol";
import { ComposeDisputeGame } from "src/l1/ComposeDisputeGame.sol";
import { ComposeETHLockbox } from "src/l1/ComposeETHLockbox.sol";
import { MockVerifier } from "test/l1/mock/MockVerifier.sol";
import { MockSuperchainConfig } from "test/l1/mock/MockSuperchainConfig.sol";

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

        // Deploy MockVerifier for tests
        mockSP1Verifier = new MockVerifier();
        mockSP1Verifier.mockVerifyProof(true);

        // Setup test actors - foundry test account #0 (key 0xac0974...)
        guardian = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        proxyAdminOwner = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        authorizedProposer = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        vm.deal(proxyAdminOwner, 1000 ether);
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

        // Build explicit test input — bypasses config.json, no env vars needed
        DeploySharedInfraInput testInput = new DeploySharedInfraInput();
        testInput.set(testInput.guardian.selector, guardian);
        testInput.set(testInput.proxyAdminOwner.selector, proxyAdminOwner);
        testInput.set(testInput.authorizedProposer.selector, authorizedProposer);
        testInput.set(testInput.sp1Verifier.selector, address(mockSP1Verifier));
        testInput.set(testInput.aggregationVkey.selector, bytes32(uint256(1)));
        testInput.set(testInput.disputeGameFinalityDelaySeconds.selector, uint256(1800));
        testInput.set(testInput.proofMaturityDelaySeconds.selector, uint256(3600));

        console.log("ComposeSetup: Deploying shared infrastructure...");

        // Deploy shared infrastructure using the script
        DeploySharedInfraOutput output = deploySharedInfra.run(testInput);

        // Store deployed contract references
        composeProxyAdmin = output.composeProxyAdmin();
        composeSuperchainConfig = output.composeSuperchainConfigProxy();
        composeDisputeGameFactory = output.composeDisputeGameFactoryProxy();
        composeAnchorStateRegistry = output.composeAnchorStateRegistryProxy();
        composeETHLockbox = output.composeETHLockboxProxy();
        composeDisputeGameImpl = output.composeDisputeGameImpl();

        // Different superchain config
        rollupSuperchainConfig = ISuperchainConfig(address(new MockSuperchainConfig()));

        // Get mock verifier from deployment
        mockSP1Verifier = MockVerifier(address(composeDisputeGameImpl.PROOF_VERIFIER()));

        console.log("ComposeSetup: Setup complete!");
        console.log("  SuperchainConfig:", address(composeSuperchainConfig));
        console.log("  DisputeGameFactory:", address(composeDisputeGameFactory));
        console.log("  AnchorStateRegistry:", address(composeAnchorStateRegistry));
        console.log("  ETHLockbox:", address(composeETHLockbox));
        console.log("  DisputeGame impl:", address(composeDisputeGameImpl));
    }
}
