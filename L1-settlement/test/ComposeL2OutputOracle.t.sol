// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {ComposeL2OutputOracle} from "../src/ComposeL2OutputOracle.sol";
import {IComposeL2OutputOracle} from "../src/interfaces/IComposeL2OutputOracle.sol";
import {IComposeL2OutputOracleTypes} from "../src/interfaces/IComposeL2OutputOracle.sol";
import {Proxy} from "@optimism/src/universal/Proxy.sol";

import {Utils} from "./Utils.sol";
import {MockVerifier} from "./mock/MockVerifier.sol";

contract ComposeL2OutputOracleUnitTest is Test, Utils {
    ComposeL2OutputOracle private l2oo;
    MockVerifier private verifier;

    address private constant APPROVED_PROPOSER = address(0x1234);
    address private constant NON_APPROVED_PROPOSER = address(0x5678);
    address private constant CHALLENGER = address(0x9ABC);
    address private constant OWNER = address(0xDEF0);

    bytes32 private constant AGGREGATION_VKEY = keccak256("aggregation_vkey");

    uint256 private constant SUBMISSION_INTERVAL = 10;
    uint256 private constant L2_BLOCK_TIME = 2;
    uint256 private constant STARTING_BLOCK_NUMBER = 1000;
    uint256 private constant FINALIZATION_PERIOD = 7 days;
    uint256 private constant FALLBACK_TIMEOUT = 2 days;

    bytes32 private constant GENESIS_CONFIG_NAME = bytes32(0);

    bytes private constant PROOF =
        hex"a4594c59162bdead7c5ac7b05e2b0576eddf5cac6ad631b71129796bfb5db2da2d14189822763aff12bbf03cad631c20a6d4c3c1eaaf9808216d174a2be0af8a996c00e5084af057ddac9445681ec7844e1b52e33a1ed84b5e8106599554107f50e3954518586d4071b44f7c22f0d954bf259a8bf0610ebb4debd43e8eb1dfb29960c9aa0d935506c2b1d79d007a576dc095325189300c0ea459a4d994854cbe82829bac16fda18d408ad0aa80ed7d0e9ccc5af167b4310b4c1430da73640e8e81daeabe0c7a4e8c3ca2b20393882c62c5815a5703f990b7166809942de5d7dfabbc4fed013ad62d57aaefbf0a600025cc420b9195936eb202a9da25acdf27f948840913";
    address private constant PROVER_ADDRESS = address(0x7890);

    bytes32 private constant OUTPUT_ROOT = keccak256("output_root");
    bytes32 private constant L1_HASH = keccak256("l1_hash");
    bytes32 private constant PARENT_SUPERBLOCK_BATCH_HASH =
        bytes32(0x66cec985afe7e41f97a2f77c876fe9015be47f18baa0bd87c59795c52887df19);
    bytes32 private constant GENESIS_SUPERBLOCK_HASH =
        bytes32(0xe7bac8efb0b12db59bbbe8667e31c486d1b6a9cc885edec48b834d943f3e2a46);
    bytes32 private constant WRONG_PARENT_SUPERBLOCK_BATCH_HASH =
        bytes32(0x4fdbc8c6797a8acaabbe9a59947714776c9cf6f78611f61c17da8d3884af41c1);
    address private constant NEW_VERIFIER = address(0xABCD);
    bytes32 private constant NEW_VKEY = keccak256("new_vkey");

    IComposeL2OutputOracleTypes.InitParams internal initParams = IComposeL2OutputOracleTypes.InitParams(
        APPROVED_PROPOSER, OWNER, AGGREGATION_VKEY, STARTING_BLOCK_NUMBER, address(verifier)
    );

    function setUp() public {
        address verifierAddress = address(new MockVerifier());
        initParams.verifier = verifierAddress;

        l2oo = deployL2OutputOracle(initParams);

        vm.warp(block.timestamp + 1000);
    }

    function test_initializer_configuresEverythingCorrectly() public {
        assertEq(l2oo.latestSuperblockNumber(), STARTING_BLOCK_NUMBER);
        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER), bytes32(0));
        assertEq(l2oo.aggregationVkey(), AGGREGATION_VKEY);
        assertEq(l2oo.verifier(), initParams.verifier);
        assertEq(l2oo.owner(), OWNER);
        assertEq(l2oo.approvedProposer(), APPROVED_PROPOSER);
        assertEq(l2oo.version(), "0.0.1");
    }

    function test_genesisSuperblockHash_matchesDomainSeparator() public {
        assertEq(l2oo.GENESIS_SUPERBLOCK_HASH(), keccak256("ComposeL2OutputOracle:GENESIS_SUPERBLOCK_HASH"));
    }

    function test_initializer_seedsGenesisHash_forFreshDeployment() public {
        ComposeL2OutputOracle freshL2oo = _deployFreshL2OutputOracle();

        assertEq(freshL2oo.latestSuperblockNumber(), 0);
        assertEq(freshL2oo.getSuperblockHash(0), GENESIS_SUPERBLOCK_HASH);
    }

    function test_setAggregationVkey_byOwner() public {
        vm.prank(OWNER);
        l2oo.setAggregationVkey(NEW_VKEY);

        assertEq(l2oo.aggregationVkey(), NEW_VKEY);
    }

    function test_setAggregationVkey_reverts_whenNotOwner() public {
        vm.expectRevert("ComposeL2OutputOracle: only owner can update aggregation vkey");
        vm.prank(NON_APPROVED_PROPOSER);
        l2oo.setAggregationVkey(NEW_VKEY);
    }

    function test_setVerifier_byOwner() public {
        vm.prank(OWNER);
        l2oo.setVerifier(NEW_VERIFIER);

        assertEq(l2oo.verifier(), NEW_VERIFIER);
    }

    function test_setVerifier_reverts_whenNotOwner() public {
        vm.expectRevert("ComposeL2OutputOracle: only owner can update verifier");
        vm.prank(NON_APPROVED_PROPOSER);
        l2oo.setVerifier(NEW_VERIFIER);
    }

    function test_initializeV2_byOwner() public {
        vm.prank(OWNER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER, PARENT_SUPERBLOCK_BATCH_HASH);

        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER), PARENT_SUPERBLOCK_BATCH_HASH);
    }

    function test_initializeV2_reverts_whenNotOwner() public {
        vm.expectRevert("ComposeL2OutputOracle: only owner can initialize v2");
        vm.prank(NON_APPROVED_PROPOSER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER, PARENT_SUPERBLOCK_BATCH_HASH);
    }

    function test_initializeV2_reverts_zeroHash() public {
        vm.expectRevert(IComposeL2OutputOracle.EmptySuperblockHash.selector);
        vm.prank(OWNER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER, bytes32(0));
    }

    function test_initializeV2_reverts_staleExpectedSuperblockNumber() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IComposeL2OutputOracle.UnexpectedSuperblockNumber.selector,
                STARTING_BLOCK_NUMBER + 1,
                STARTING_BLOCK_NUMBER
            )
        );
        vm.prank(OWNER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
    }

    function test_initializeV2_reverts_whenCalledTwice() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);

        vm.expectRevert("Initializable: contract is already initialized");
        vm.prank(OWNER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER, PARENT_SUPERBLOCK_BATCH_HASH);
    }

    function test_initializeV2_reverts_whenGenesisHashAlreadySeeded() public {
        ComposeL2OutputOracle freshL2oo = _deployFreshL2OutputOracle();

        vm.expectRevert(
            abi.encodeWithSelector(
                IComposeL2OutputOracle.SuperblockHashAlreadySeeded.selector, 0, GENESIS_SUPERBLOCK_HASH
            )
        );
        vm.prank(OWNER);
        freshL2oo.initializeV2(0, PARENT_SUPERBLOCK_BATCH_HASH);
    }

    function test_proposeL2Output_acceptsFirstProposalFromGenesis() public {
        ComposeL2OutputOracle freshL2oo = _deployFreshL2OutputOracle();
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(1, GENESIS_SUPERBLOCK_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        freshL2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);

        assertEq(freshL2oo.latestSuperblockNumber(), 1);
        assertEq(freshL2oo.getSuperblockHash(1), keccak256(abi.encode(superBlockAggOutputs)));
    }

    function test_proposeL2Output_byApprovedProposer() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);

        assertEq(l2oo.latestSuperblockNumber(), STARTING_BLOCK_NUMBER + 1);
        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER + 1), keccak256(abi.encode(superBlockAggOutputs)));
    }

    function test_proposeL2Output_reverts_invalidSuperblockNumber() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 2, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.expectRevert(IComposeL2OutputOracle.InvalidSuperBlockNumber.selector);
        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);
    }

    function test_proposeL2Output_reverts_notApprovedProposer() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        vm.expectRevert(IComposeL2OutputOracle.UnauthorizedProposer.selector);
        vm.prank(NON_APPROVED_PROPOSER, NON_APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);
    }

    function test_proposeL2Output_reverts_zeroOutputRoot() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.expectRevert(IComposeL2OutputOracle.EmptyOutputRoot.selector);
        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(bytes32(0), L1_HASH, extraData);
    }

    function test_proposeL2Output_reverts_missingSuperblockHash() public {
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.expectRevert(
            abi.encodeWithSelector(IComposeL2OutputOracle.MissingSuperblockHash.selector, STARTING_BLOCK_NUMBER)
        );
        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);
    }

    function test_proposeL2Output_reverts_invalidParentSuperblockHash() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, WRONG_PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IComposeL2OutputOracle.InvalidParentSuperblockHash.selector,
                PARENT_SUPERBLOCK_BATCH_HASH,
                WRONG_PARENT_SUPERBLOCK_BATCH_HASH
            )
        );
        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);
    }

    function test_proposeL2Output_reverts_proofVerificationFails() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory superBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory extraData = abi.encode(superBlockAggOutputs, PROOF);

        MockVerifier(initParams.verifier).mockVerifyProof(false);

        vm.expectRevert("MockVerifier: Proof verification failed");
        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, extraData);

        assertEq(l2oo.latestSuperblockNumber(), STARTING_BLOCK_NUMBER);
        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER + 1), bytes32(0));
    }

    function test_proposeL2Output_acceptsTwoConsecutiveProposals() public {
        _seedCurrentSuperblockHash(PARENT_SUPERBLOCK_BATCH_HASH);
        MockVerifier(initParams.verifier).mockVerifyProof(true);

        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory firstSuperBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 1, PARENT_SUPERBLOCK_BATCH_HASH);
        bytes memory firstExtraData = abi.encode(firstSuperBlockAggOutputs, PROOF);

        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, firstExtraData);

        bytes32 firstSuperblockHash = keccak256(abi.encode(firstSuperBlockAggOutputs));
        IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory secondSuperBlockAggOutputs =
            _superblockOutputs(STARTING_BLOCK_NUMBER + 2, firstSuperblockHash);
        bytes memory secondExtraData = abi.encode(secondSuperBlockAggOutputs, PROOF);

        vm.prank(APPROVED_PROPOSER, APPROVED_PROPOSER);
        l2oo.proposeL2Output(OUTPUT_ROOT, L1_HASH, secondExtraData);

        assertEq(l2oo.latestSuperblockNumber(), STARTING_BLOCK_NUMBER + 2);
        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER + 1), firstSuperblockHash);
        assertEq(l2oo.getSuperblockHash(STARTING_BLOCK_NUMBER + 2), keccak256(abi.encode(secondSuperBlockAggOutputs)));
    }

    function test_version_returnsCorrectVersion() public {
        assertEq(l2oo.version(), "0.0.1");
    }

    function _seedCurrentSuperblockHash(bytes32 superblockHash) internal {
        vm.prank(OWNER);
        l2oo.initializeV2(STARTING_BLOCK_NUMBER, superblockHash);
    }

    function _deployFreshL2OutputOracle() internal returns (ComposeL2OutputOracle) {
        IComposeL2OutputOracleTypes.InitParams memory freshInitParams = initParams;
        freshInitParams.startingSuperBlockNumber = 0;

        return deployL2OutputOracle(freshInitParams);
    }

    function _superblockOutputs(uint256 superblockNumber, bytes32 parentSuperblockBatchHash)
        internal
        pure
        returns (IComposeL2OutputOracleTypes.SuperblockAggregationOutputs memory)
    {
        return IComposeL2OutputOracleTypes.SuperblockAggregationOutputs({
            superblockNumber: superblockNumber,
            parentSuperblockBatchHash: parentSuperblockBatchHash,
            bootInfo: new IComposeL2OutputOracleTypes.BootInfoStruct[](0)
        });
    }
}
