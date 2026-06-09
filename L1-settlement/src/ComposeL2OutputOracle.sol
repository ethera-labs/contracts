// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ISemver} from "interfaces/universal/ISemver.sol";
import {ISP1Verifier} from "@sp1-contracts/src/ISP1Verifier.sol";
import {IComposeL2OutputOracle} from "./interfaces/IComposeL2OutputOracle.sol";

contract ComposeL2OutputOracle is Initializable, ISemver, IComposeL2OutputOracle {
    uint32 public constant COMPOSE_GAME_TYPE = 5555;

    /// @notice The version of the initializer on the contract. Used for managing upgrades.
    uint8 public constant INITIALIZER_VERSION = 1;

    /// @notice The number of the last superblock recorded in this contract.
    uint256 public superBlockNumber;

    /// @notice Hash of each recorded superblock aggregation output.
    mapping(uint256 => bytes32) private superblockHashes;

    /// @notice The verification key of the aggregation SP1 program.
    bytes32 public aggregationVkey;

    /// @notice The deployed SP1Verifier contract to verify proofs.
    address public verifier;

    /// @notice The owner of the contract, who has admin permissions.
    address public owner;

    address public approvedProposer;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _initParams The initialization parameters for the contract.
    function initialize(InitParams memory _initParams) public reinitializer(INITIALIZER_VERSION) {
        superBlockNumber = _initParams.startingSuperBlockNumber;

        aggregationVkey = _initParams.aggregationVkey;

        verifier = _initParams.verifier;

        owner = _initParams.owner;

        approvedProposer = _initParams.proposer;
    }

    /// @notice Accepts an outputRoot and the timestamp of the corresponding L2 block.
    ///         The timestamp must be equal to the current value returned by `nextTimestamp()` in
    ///         order to be accepted. This function may only be called by the Proposer.
    /// @param _outputRoot    The L2 output of the checkpoint block.
    /// @param _extraData The public values to veryfy the proof (SuperblockAggregationOutputs) and the SuperBlock proof.
    /// @dev Modified the function signature to exclude the `_l1BlockHash` parameter, as it's redundant
    ///      for OP Succinct given the `_l1BlockNumber` parameter.
    /// @dev Security Note: This contract uses `tx.origin` for proposer permission control due to usage of this contract
    ///      in the OPSuccinctDisputeGame, created via DisputeGameFactory using the Clone With Immutable Arguments (CWIA) pattern.
    ///
    ///      In this setup:
    ///      - `msg.sender` is the newly created game contract, not an approved proposer.
    ///      - `tx.origin` identifies the actual user initiating the transaction.
    ///
    ///      While `tx.origin` can be vulnerable in general, it is safe here because:
    ///      - Only trusted proposers/relayers call this contract.
    ///      - Proposers are expected to interact solely with trusted contracts.
    ///
    ///      As long as proposers avoid untrusted contracts, `tx.origin` is as secure as `msg.sender` in this context.
    function proposeL2Output(bytes32 _outputRoot, bytes32 _l1Hash, bytes memory _extraData) external {
        if (tx.origin != approvedProposer) {
            revert UnauthorizedProposer();
        }

        (SuperblockAggregationOutputs memory superBlockAggOutputs, bytes memory proof) =
            abi.decode(_extraData, (SuperblockAggregationOutputs, bytes));

        if (_outputRoot == bytes32(0)) {
            revert EmptyOutputRoot();
        }

        uint256 nextSuperBlockNumber = superBlockNumber + 1;
        if (superBlockAggOutputs.superblockNumber != nextSuperBlockNumber) {
            revert InvalidSuperBlockNumber();
        }

        ISP1Verifier(verifier)
            .verifyProof(aggregationVkey, bytes32ToBytes(sha256(abi.encode(superBlockAggOutputs))), proof);

        superBlockNumber = nextSuperBlockNumber;
        superblockHashes[nextSuperBlockNumber] = keccak256(abi.encode(superBlockAggOutputs));

        // TODO
        // Store block data if needed for portal legacy support ?

        BootInfoStruct memory bootInfo;

        for (uint256 i = 0; i < superBlockAggOutputs.bootInfo.length; i++) {
            bootInfo = superBlockAggOutputs.bootInfo[i];

            // TODO I think we need a way to identify the rollup chain, maybe we can use the rollupConfigHash?
            emit L2OutputProposed(
                superBlockAggOutputs.superblockNumber, bootInfo.l2BlockNumber, bootInfo.l2PostRoot, block.timestamp
            );
        }

        emit SuperblockOutputProposed(
            superBlockAggOutputs.superblockNumber,
            block.number,
            superBlockAggOutputs.parentSuperblockBatchHash,
            block.timestamp
        );
    }

    function latestSuperblockNumber() external view returns (uint256) {
        return superBlockNumber;
    }

    function getSuperblockHash(uint256 _superblockNumber) external view returns (bytes32) {
        return superblockHashes[_superblockNumber];
    }

    // TODO remove in prod
    function setAggregationVkey(bytes32 _aggregationVkey) external {
        require(msg.sender == owner, "ComposeL2OutputOracle: only owner can update aggregation vkey");
        aggregationVkey = _aggregationVkey;
        emit AggregationVkeyUpdated(_aggregationVkey);
    }

    // TODO remove in prod
    function setVerifier(address _verifier) external {
        require(msg.sender == owner, "ComposeL2OutputOracle: only owner can update verifier");
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    // TODO remove in prod
    function setApprovedProposer(address _approvedProposer) external {
        require(msg.sender == owner, "ComposeL2OutputOracle: only owner can update approved proposer");
        approvedProposer = _approvedProposer;
        emit ApprovedProposerUpdated(approvedProposer);
    }

    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    function bytes32ToBytes(bytes32 input) public pure returns (bytes memory) {
        bytes memory b = new bytes(32);
        assembly {
            mstore(add(b, 32), input)
        }
        return b;
    }
}
