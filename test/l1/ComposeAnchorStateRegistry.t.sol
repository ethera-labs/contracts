// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ComposeCommonTest} from "test/l1/setup/ComposeCommonTest.sol";
import {GameType, Hash} from "@optimism/src/dispute/lib/Types.sol";
import {IDisputeGame} from "@optimism/interfaces/dispute/IDisputeGame.sol";

/// @title ComposeAnchorStateRegistryTest
/// @notice Tests for the ComposeAnchorStateRegistry contract
contract ComposeAnchorStateRegistryTest is ComposeCommonTest {
    // ============ Initialization Tests ============

    function test_initialization_success() public view {
        assertEq(address(composeAnchorStateRegistry.disputeGameFactory()), address(composeDisputeGameFactory), "DGF mismatch");

        assertEq(address(composeAnchorStateRegistry.superchainConfig()), address(composeSuperchainConfig), "SuperchainConfig mismatch");

        assertEq(composeAnchorStateRegistry.respectedGameType().raw(), 5555, "Respected game type mismatch");
    }

    // ============ Pause Tests ============

    function test_paused_returnsFalseInitially() public view {
        assertFalse(composeAnchorStateRegistry.paused());
    }

    function test_paused_returnsTrueWhenGlobalPaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        assertTrue(composeAnchorStateRegistry.paused());
    }

    function test_paused_returnsTrueWhenASRSpecificallyPaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(composeAnchorStateRegistry));

        assertTrue(composeAnchorStateRegistry.paused());
    }

    function test_paused_returnsFalseAfterUnpause() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        vm.prank(guardian);
        composeSuperchainConfig.unpause(address(0));

        assertFalse(composeAnchorStateRegistry.paused());
    }

    // ============ Respected Game Type Tests ============

    function test_setRespectedGameType_success() public {
        GameType newGameType = GameType.wrap(9999);

        vm.prank(guardian);
        composeAnchorStateRegistry.setRespectedGameType(newGameType);

        assertEq(composeAnchorStateRegistry.respectedGameType().raw(), 9999);
    }

    function test_setRespectedGameType_revertsIfNotGuardian() public {
        GameType newGameType = GameType.wrap(9999);

        vm.prank(alice);
        vm.expectRevert();
        composeAnchorStateRegistry.setRespectedGameType(newGameType);
    }

    // ============ Retirement Timestamp Tests ============

    function test_updateRetirementTimestamp_success() public {
        uint256 initialTimestamp = composeAnchorStateRegistry.retirementTimestamp();

        _advanceTime(1 days);

        vm.prank(guardian);
        composeAnchorStateRegistry.updateRetirementTimestamp();

        uint256 newTimestamp = composeAnchorStateRegistry.retirementTimestamp();
        assertTrue(newTimestamp > initialTimestamp, "Timestamp should increase");
        assertEq(newTimestamp, block.timestamp, "Should be current timestamp");
    }

    function test_updateRetirementTimestamp_revertsIfNotGuardian() public {
        vm.prank(alice);
        vm.expectRevert();
        composeAnchorStateRegistry.updateRetirementTimestamp();
    }

    // ============ Blacklist Tests ============

    function test_blacklistDisputeGame_success() public {
        address mockGame = makeAddr("mockGame");

        vm.prank(guardian);
        composeAnchorStateRegistry.blacklistDisputeGame(IDisputeGame(mockGame));

        assertTrue(composeAnchorStateRegistry.disputeGameBlacklist(IDisputeGame(mockGame)));
    }

    function test_blacklistDisputeGame_revertsIfNotGuardian() public {
        address mockGame = makeAddr("mockGame");

        vm.prank(alice);
        vm.expectRevert();
        composeAnchorStateRegistry.blacklistDisputeGame(IDisputeGame(mockGame));
    }

    function test_isGameBlacklisted_returnsFalseForNonBlacklisted() public {
        address mockGame = makeAddr("mockGame");

        assertFalse(composeAnchorStateRegistry.isGameBlacklisted(IDisputeGame(mockGame)));
    }

    function test_isGameBlacklisted_returnsTrueForBlacklisted() public {
        address mockGame = makeAddr("mockGame");

        vm.prank(guardian);
        composeAnchorStateRegistry.blacklistDisputeGame(IDisputeGame(mockGame));

        assertTrue(composeAnchorStateRegistry.isGameBlacklisted(IDisputeGame(mockGame)));
    }

    // ============ Anchor Root Tests ============

    function test_getAnchorRoot_returnsStartingAnchorInitially() public view {
        (Hash root, uint256 l2SequenceNumber) = composeAnchorStateRegistry.getAnchorRoot();

        // Should return the placeholder starting anchor root (set to 1 during deployment)
        assertEq(root.raw(), bytes32(uint256(1)), "Starting root should be placeholder (1)");
        assertEq(l2SequenceNumber, 0, "Starting sequence should be zero");
    }

    // ============ View Function Tests ============

    function test_disputeGameFinalityDelaySeconds_returnsCorrectValue() public view {
        uint256 delay = composeAnchorStateRegistry.disputeGameFinalityDelaySeconds();

        // Should match the value from deployment (default 3.5 days)
        assertTrue(delay > 0, "Delay should be set");
    }
}
