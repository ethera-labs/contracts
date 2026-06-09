// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

interface IComposeL2OutputOracleTypes {
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

interface IComposeL2OutputOracle is IComposeL2OutputOracleTypes {
    event L2OutputProposed(
        uint256 indexed superBlockNumber, uint256 indexed l2BlockNumber, bytes32 indexed outputRoot, uint256 l1Timestamp
    );

    event SuperblockOutputProposed(
        uint256 indexed superBlockNumber, uint256 indexed l1BlockNumber, bytes32 indexed outputRoot, uint256 l1Timestamp
    );

    event AggregationVkeyUpdated(bytes32 indexed aggregationVkey);
    event VerifierUpdated(address indexed verifier);
    event ApprovedProposerUpdated(address indexed approvedProposer);
    event SuperblockHashSeeded(uint256 indexed superblockNumber, bytes32 indexed superblockHash);

    error UnauthorizedProposer();
    error InvalidSuperBlockNumber();
    error EmptyOutputRoot();
    error EmptySuperblockHash();
    error SuperblockHashAlreadySeeded(uint256 superblockNumber, bytes32 existingHash);
    error MissingSuperblockHash(uint256 superblockNumber);
    error InvalidParentSuperblockHash(bytes32 expected, bytes32 actual);
    error UnexpectedSuperblockNumber(uint256 expected, uint256 actual);

    function proposeL2Output(bytes32 _outputRoot, bytes32 _l1Hash, bytes memory _extraData) external;

    function initializeV2(uint256 expectedSuperblockNumber, bytes32 currentSuperblockHash) external;

    function latestSuperblockNumber() external view returns (uint256);

    function getSuperblockHash(uint256 _superblockNumber) external view returns (bytes32);
}
