// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import {Clone} from "@optimism/lib/solady/src/utils/Clone.sol";
import {ISemver} from "@optimism/interfaces/universal/ISemver.sol";
import {GameNotInProgress, GameNotFinalized, GamePaused} from "@optimism/src/dispute/lib/Errors.sol";
import {Hashing} from "@optimism/src/libraries/Hashing.sol";
import {Types} from "@optimism/src/libraries/Types.sol";
import { Timestamp, GameStatus, GameType, Claim, Hash } from "@optimism/src/dispute/lib/Types.sol";
import {ISP1Verifier} from "@sp1-contracts/src/ISP1Verifier.sol";
import {IComposeDisputeGame, IDisputeGame} from "./interfaces/ICompose.sol";
import {IComposeAnchorStateRegistry} from "./interfaces/IComposeAnchorStateRegistry.sol";

contract ComposeDisputeGame is ISemver, Clone, IComposeDisputeGame {
    uint32 public constant COMPOSE_GAME_TYPE = 5555;

    bytes32 public immutable AGGREGATION_VKEY;

    ISP1Verifier public immutable PROOF_VERIFIER;
    IComposeAnchorStateRegistry public immutable ANCHOR_STATE_REGISTRY;
    address public immutable AUTHORIZED_PROPOSER;

    /// @notice The timestamp of the game's global creation.
    Timestamp public createdAt;

    /// @notice The timestamp of the game's global resolution.
    Timestamp public resolvedAt;

    /// @notice Returns the current status of the game.
    GameStatus public status;

    /// @notice A boolean for whether or not the game type was respected when the game was created.
    bool public wasRespectedGameTypeWhenCreated;

    /// @notice Tracks the last accepted superblock number to enforce monotonically increasing inputs.
    uint256 public lastSuperblockNumber;

    /// @notice Tracks the latest output for each rollup config hash.
    mapping(bytes32 => RollupOutput) public latestOutputsByConfig;

    /// @custom:semver 1.0.0
    string public constant version = "v1.0.0";

    constructor(
        address _proofVerifier,
        bytes32 _aggregationVkey,
        IComposeAnchorStateRegistry _asr,
        address _authorizedProposer
    ) {
        if (_proofVerifier == address(0)) revert InvalidVerifier();
        if (address(_asr) == address(0)) revert InvalidASR();
        PROOF_VERIFIER = ISP1Verifier(_proofVerifier);
        AGGREGATION_VKEY = _aggregationVkey;
        ANCHOR_STATE_REGISTRY = _asr;
        AUTHORIZED_PROPOSER = _authorizedProposer;
    }

    function initialize() external payable {
        if (Timestamp.unwrap(createdAt) != 0) revert AlreadyInitialized();

        if (gameCreator() != AUTHORIZED_PROPOSER) revert UnauthorizedProposer();

        createdAt = Timestamp.wrap(uint64(block.timestamp));
        status = GameStatus.IN_PROGRESS;
        wasRespectedGameTypeWhenCreated = (GameType.unwrap(
            ANCHOR_STATE_REGISTRY.respectedGameType()
        ) == GameType.unwrap(gameType()));

        (
            SuperblockAggregationOutputs memory aggOutputs,
            Types.SuperRootProof memory superRootProof,
            bytes memory proof
        ) = decodeExtraData();

        if (proof.length == 0) revert MissingAggregationProof();
        if (superRootProof.timestamp > uint64(block.timestamp))
            revert FutureTimestampProposed(
                superRootProof.timestamp,
                uint64(block.timestamp)
            );

        bytes32 claimedRoot = rootClaim().raw();
        bytes32 expectedRoot = Hashing.hashSuperRootProof(superRootProof);
        if (claimedRoot != expectedRoot)
            revert InvalidRootClaim(expectedRoot, claimedRoot);

        if (aggOutputs.superblockNumber <= lastSuperblockNumber) {
            revert InvalidSuperblockOrdering(
                lastSuperblockNumber,
                aggOutputs.superblockNumber
            );
        }

        if (superRootProof.outputRoots.length != aggOutputs.bootInfo.length) {
            revert OutputLengthMismatch(
                aggOutputs.bootInfo.length,
                superRootProof.outputRoots.length
            );
        }

        PROOF_VERIFIER.verifyProof(
            AGGREGATION_VKEY,
            bytes32ToBytes(sha256(abi.encode(aggOutputs))),
            proof
        );

        lastSuperblockNumber = aggOutputs.superblockNumber;

        uint256 rootsLen = superRootProof.outputRoots.length;
        for (uint256 i; i < rootsLen; i++) {
            Types.OutputRootWithChainId
                memory outputRootWithChainId = superRootProof.outputRoots[i];
            BootInfoStruct memory bootInfo = aggOutputs.bootInfo[
                i
            ];

            if (outputRootWithChainId.root != bootInfo.l2PostRoot) {
                revert OutputRootMismatch(
                    outputRootWithChainId.chainId,
                    bootInfo.l2PostRoot,
                    outputRootWithChainId.root
                );
            }

            latestOutputsByConfig[bootInfo.rollupConfigHash] = RollupOutput({
                l1Head: bootInfo.l1Head,
                outputRoot: outputRootWithChainId.root,
                l2BlockNumber: bootInfo.l2BlockNumber
            });

            emit L2OutputProposed(
                aggOutputs.superblockNumber,
                outputRootWithChainId.chainId,
                bootInfo.l2BlockNumber,
                bootInfo.rollupConfigHash,
                outputRootWithChainId.root,
                bootInfo.l1Head,
                block.timestamp
            );
        }

        emit SuperblockProposed(
            aggOutputs.superblockNumber,
            aggOutputs.parentSuperblockBatchHash,
            superRootProof.timestamp,
            block.number,
            expectedRoot
        );

        this.resolve();
    }

    /// @dev May only be called if the `status` is `IN_PROGRESS`.
    /// @return status_ The status of the game after resolution.
    function resolve() external returns (GameStatus status_) {
        // INVARIANT: Resolution cannot occur unless the game is currently in progress.
        if (status != GameStatus.IN_PROGRESS) revert GameNotInProgress();

        resolvedAt = Timestamp.wrap(uint64(block.timestamp));
        status_ = GameStatus.DEFENDER_WINS;

        emit Resolved(status = status_);
    }

    /// @notice Attempts to update the AnchorStateRegistry with this game as the new anchor.
    ///         Safe to call multiple times; the ASR enforces validity and monotonicity.
    function closeGame() external {
        if (ANCHOR_STATE_REGISTRY.paused()) {
            revert GamePaused();
        }

        // Game must be finalized according to the AnchorStateRegistry.
        bool finalized = ANCHOR_STATE_REGISTRY.isGameFinalized(
            IDisputeGame(address(this))
        );
        if (!finalized) {
            revert GameNotFinalized();
        }

        // Best-effort; ignore failures (e.g., finality delay not yet elapsed).
        try
            ANCHOR_STATE_REGISTRY.setAnchorState(IDisputeGame(address(this)))
        {} catch {}

        emit GameClosed();
    }

    /// @return gameType_ The type of proof system being used.
    function gameType() public pure returns (GameType) {
        return GameType.wrap(COMPOSE_GAME_TYPE);
    }

    /// @notice Getter for the creator of the dispute game.
    /// @dev `clones-with-immutable-args` argument #1
    /// @return The creator of the dispute game.
    function gameCreator() public pure returns (address) {
        return _getArgAddress(0x00);
    }

    /// @notice Getter for the root claim.
    /// @dev `clones-with-immutable-args` argument #2
    /// @return The root claim of the DisputeGame.
    function rootClaim() public pure returns (Claim) {
        return Claim.wrap(_getArgBytes32(0x14));
    }

    /// @notice Getter for the parent hash of the L1 block when the dispute game was created.
    /// @dev `clones-with-immutable-args` argument #3
    /// @return The parent hash of the L1 block when the dispute game was created.
    function l1Head() public pure returns (Hash) {
        return Hash.wrap(_getArgBytes32(0x34));
    }

    /// @notice Getter for the extra data.
    /// @dev `clones-with-immutable-args` argument #4
    /// @return extraData_ Any extra data supplied to the dispute game contract by the creator.
    function extraData() public pure returns (bytes memory extraData_) {
        uint256 len;
        assembly {
            // 0x54 is the starting point of the extra data in the calldata.
            // calldataload(sub(calldatasize(), 2)) loads the last 2 bytes of the calldata, which gives the length of the immutable args.
            // shr(240, calldataload(sub(calldatasize(), 2))) masks the last 30 bytes loaded in the previous step, so only the length of the immutable args is left.
            // sub(sub(...)) subtracts the length of the immutable args (2 bytes) and the starting point of the extra data (0x54).
            len := sub(
                sub(shr(240, calldataload(sub(calldatasize(), 2))), 2),
                0x54
            )
        }
        extraData_ = _getArgBytes(0x54, len);
    }

    function l2BlockNumber() external pure returns (uint256 l2BlockNumber_) {
        return 0;
    }

    function gameData()
        external
        pure
        returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_)
    {
        gameType_ = gameType();
        rootClaim_ = rootClaim();
        extraData_ = extraData();
    }

    /// @notice ASR uses this to enforce that new anchors are strictly newer than the current anchor.
    function l2SequenceNumber()
        external
        pure
        returns (uint256 l2SequenceNumber_)
    {
        (
            SuperblockAggregationOutputs memory aggOutputs,
            ,

        ) = decodeExtraData();
        l2SequenceNumber_ = aggOutputs.superblockNumber;
    }

    /// @notice Returns the AnchorStateRegistry address this game is registered with.
    function anchorStateRegistry()
        external
        view
        returns (IComposeAnchorStateRegistry registry_)
    {
        registry_ = ANCHOR_STATE_REGISTRY;
    }

    function bytes32ToBytes(bytes32 input) private pure returns (bytes memory) {
        bytes memory b = new bytes(32);
        assembly {
            mstore(add(b, 32), input)
        }
        return b;
    }

    function decodeExtraData()
        private
        pure
        returns (
            SuperblockAggregationOutputs memory aggOutputs,
            Types.SuperRootProof memory superRootProof,
            bytes memory proof
        )
    {
        return
            abi.decode(
                extraData(),
                (
                    SuperblockAggregationOutputs,
                    Types.SuperRootProof,
                    bytes
                )
            );
    }
}
