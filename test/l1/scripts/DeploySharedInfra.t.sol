// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ComposeCommonTest } from "test/l1/setup/ComposeCommonTest.sol";
import { GameType } from "@optimism/src/dispute/lib/Types.sol";

/// @title DeploySharedInfraTest
/// @notice Tests the Phase 1 deployment script
/// @dev Uses ComposeCommonTest which runs the deployment automatically
contract DeploySharedInfraTest is ComposeCommonTest {
    
    function test_deployment_succeeds() public view {
        // Verify all contracts deployed
        assertTrue(address(composeProxyAdmin) != address(0), "ProxyAdmin not deployed");
        assertTrue(address(composeSuperchainConfig) != address(0), "SuperchainConfig not deployed");
        assertTrue(address(composeDisputeGameFactory) != address(0), "DGF not deployed");
        assertTrue(address(composeAnchorStateRegistry) != address(0), "ASR not deployed");
        assertTrue(address(composeETHLockbox) != address(0), "Lockbox not deployed");
        assertTrue(address(composeDisputeGameImpl) != address(0), "DisputeGame not deployed");
    }
    
    function test_superchainConfig_initialization() public view {
        address guardianAddr = composeSuperchainConfig.guardian();
        
        assertTrue(guardianAddr != address(0), "Guardian not set");
        assertEq(guardianAddr, guardian, "Guardian should match test actor");
    }
    
    function test_anchorStateRegistry_initialization() public view {
        address dgf = address(composeAnchorStateRegistry.disputeGameFactory());
        GameType respectedType = composeAnchorStateRegistry.respectedGameType();
        
        assertEq(dgf, address(composeDisputeGameFactory), "DGF mismatch");
        assertEq(respectedType.raw(), 5555, "Game type mismatch");
    }
    
    function test_ethLockbox_initialization() public view {
        address sc = address(composeETHLockbox.superchainConfig());
        
        assertEq(sc, address(composeSuperchainConfig), "SuperchainConfig mismatch");
        assertFalse(composeETHLockbox.paused(), "Should not be paused");
    }
    
    function test_disputeGameFactory_gameRegistration() public view {
        address gameImpl = address(
            composeDisputeGameFactory.gameImpls(GameType.wrap(5555))
        );
        
        assertEq(gameImpl, address(composeDisputeGameImpl), "Game not registered");
    }
}
