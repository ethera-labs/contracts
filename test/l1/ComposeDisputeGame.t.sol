// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ComposeCommonTest } from "test/l1/setup/ComposeCommonTest.sol";
import { GameType, GameStatus, Claim } from "@optimism/src/dispute/lib/Types.sol";

/// @title ComposeDisputeGameTest
/// @notice Tests for the ComposeDisputeGame contract
contract ComposeDisputeGameTest is ComposeCommonTest {
    
    // ============ Initialization Tests ============

    function test_implementation_deployed() public view {
        assertTrue(address(composeDisputeGameImpl) != address(0), "Game impl not deployed");
    }

    function test_implementation_hasCorrectVerifier() public view {
        assertEq(
            address(composeDisputeGameImpl.PROOF_VERIFIER()),
            address(mockSP1Verifier),
            "Verifier mismatch"
        );
    }

    function test_implementation_hasCorrectASR() public view {
        assertEq(
            address(composeDisputeGameImpl.ANCHOR_STATE_REGISTRY()),
            address(composeAnchorStateRegistry),
            "ASR mismatch"
        );
    }

    function test_implementation_hasCorrectAuthorizedProposer() public view {
        assertEq(
            composeDisputeGameImpl.AUTHORIZED_PROPOSER(),
            authorizedProposer,
            "Authorized proposer mismatch"
        );
    }

    // ============ Factory Registration Tests ============

    function test_factory_hasGameRegistered() public view {
        address gameImpl = address(
            composeDisputeGameFactory.gameImpls(GameType.wrap(5555))
        );
        
        assertEq(gameImpl, address(composeDisputeGameImpl), "Game not registered in factory");
    }

    // ============ Game Type Tests ============

    function test_gameType_isCorrect() public view {
        assertEq(composeDisputeGameImpl.COMPOSE_GAME_TYPE(), 5555, "Game type mismatch");
    }

    // ============ Version Tests ============

    function test_version_isSet() public view {
        string memory ver = composeDisputeGameImpl.version();
        assertTrue(bytes(ver).length > 0, "Version not set");
    }

    // ============ Integration Tests ============

    function test_asr_respectsGameType() public view {
        GameType respectedType = composeAnchorStateRegistry.respectedGameType();
        assertEq(respectedType.raw(), 5555, "ASR doesn't respect COMPOSE game type");
    }
}
