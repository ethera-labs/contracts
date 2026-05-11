// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {IDisputeGame} from "@optimism/interfaces/dispute/IDisputeGame.sol";

interface IComposeTypes {
    struct InitParams {
        address proposer;
        address owner;
        bytes32 aggregationVkey;
        uint256 startingSuperBlockNumber;
        address verifier;
    }

    struct SuperblockAggregationOutputs {
        uint256 superblockNumber;
        bytes32 parentSuperblockBatchHash;
        BootInfoStruct[] bootInfo;
    }

    struct BootInfoStruct {
        bytes32 l1Head;
        bytes32 l2PreRoot;
        bytes32 l2PostRoot;
        uint64 l2BlockNumber;
        bytes32 rollupConfigHash;
    }
}

interface IComposeDisputeGame is IDisputeGame, IComposeTypes {
    event L2OutputProposed(
        uint256 indexed superblockNumber,
        uint256 indexed chainId,
        uint256 indexed l2BlockNumber,
        bytes32 rollupConfigHash,
        bytes32 outputRoot,
        bytes32 l1Head,
        uint256 l1Timestamp
    );

    event SuperblockProposed(
        uint256 indexed superblockNumber,
        bytes32 parentSuperblockBatchHash,
        uint64 superblockTimestamp,
        uint256 l1BlockNumber,
        bytes32 superRootClaim
    );

    /// @notice Emitted when the game is closed.
    event GameClosed();

    struct RollupOutput {
        bytes32 l1Head;
        bytes32 outputRoot;
        uint64 l2BlockNumber;
    }

    error UnauthorizedProposer();
    error EmptyOutputRoot();
    error AlreadyInitialized();
    error InvalidRootClaim(bytes32 expected, bytes32 provided);
    error InvalidSuperblockOrdering(uint256 previous, uint256 current);
    error MissingAggregationProof();
    error OutputLengthMismatch(uint256 bootLength, uint256 rootLength);
    error OutputRootMismatch(uint256 chainId, bytes32 expected, bytes32 actual);
    error InvalidVerifier();
    error FutureTimestampProposed(uint64 submitted, uint64 current);
    error InvalidASR();
}
