// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ComposeCommonTest} from "test/l1/setup/ComposeCommonTest.sol";
import {GameType} from "@optimism/src/dispute/lib/Types.sol";

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
        assertTrue(address(l1DepositWhitelist) != address(0), "Whitelist not deployed");
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

    function test_l1DepositWhitelist_initialization() public view {
        assertTrue(l1DepositWhitelist.hasRole(l1DepositWhitelist.DEFAULT_ADMIN_ROLE(), proxyAdminOwner), "Default admin missing");
        assertTrue(l1DepositWhitelist.hasRole(l1DepositWhitelist.DEPOSIT_WHITELIST_ROLE(), proxyAdminOwner), "Whitelist admin missing");
        assertFalse(l1DepositWhitelist.portalDepositAllowed(address(0x1234)), "Portal should default false");
        assertFalse(l1DepositWhitelist.erc20DepositAllowed(address(0x1234), address(0x5678)), "Token should default false");
    }

    function test_disputeGameFactory_gameRegistration() public view {
        address gameImpl = address(composeDisputeGameFactory.gameImpls(GameType.wrap(5555)));

        assertEq(gameImpl, address(composeDisputeGameImpl), "Game not registered");
    }
}
