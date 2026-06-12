// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISuperchainConfig} from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import {IOptimismPortal2 as IOptimismPortal} from "@optimism/interfaces/L1/IOptimismPortal2.sol";
import {ISystemConfig} from "@optimism/interfaces/L1/ISystemConfig.sol";
import {IDisputeGameFactory} from "@optimism/interfaces/dispute/IDisputeGameFactory.sol";
import {IDisputeGame} from "@optimism/interfaces/dispute/IDisputeGame.sol";
import {IAnchorStateRegistry} from "@optimism/interfaces/dispute/IAnchorStateRegistry.sol";
import {IProxyAdmin} from "@optimism/interfaces/universal/IProxyAdmin.sol";
import {IETHLockbox} from "@optimism/interfaces/L1/IETHLockbox.sol";
import {GameType} from "@optimism/src/dispute/lib/Types.sol";
import {Types} from "@optimism/src/libraries/Types.sol";

/// @title MockPortal
/// @notice Mock portal for testing ETHLockbox
contract MockPortal is IOptimismPortal {
    ISuperchainConfig internal _superchainConfig;

    constructor(ISuperchainConfig superchainConfig_) {
        _superchainConfig = superchainConfig_;
    }

    function superchainConfig() external view returns (ISuperchainConfig) {
        return _superchainConfig;
    }

    function l2Sender() external pure returns (address) {
        return address(0);
    }

    function donateETH() external payable {}

    receive() external payable {}

    // Stub implementations for IOptimismPortal2 interface - only what's needed for ETHLockbox
    function guardian() external pure returns (address) {
        return address(0);
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function l2Oracle() external pure returns (address) {
        return address(0);
    }

    function systemConfig() external pure returns (ISystemConfig) {
        return ISystemConfig(address(0));
    }

    function disputeGameFactory() external pure returns (IDisputeGameFactory) {
        return IDisputeGameFactory(address(0));
    }

    function proofMaturityDelaySeconds() external pure returns (uint256) {
        return 0;
    }

    function disputeGameFinalityDelaySeconds() external pure returns (uint256) {
        return 0;
    }

    function respectedGameType() external pure returns (GameType) {
        return GameType.wrap(0);
    }

    function numProofSubmitters() external pure returns (uint256) {
        return 0;
    }

    function provenWithdrawals(bytes32, address) external pure returns (IDisputeGame disputeGameProxy, uint64 timestamp) {
        return (IDisputeGame(address(0)), 0);
    }

    function proofSubmitters(address) external pure returns (bool) {
        return false;
    }
    function checkWithdrawal(bytes32, address) external pure {}

    function blacklistedDisputeGames(address) external pure returns (bool) {
        return false;
    }
    function setRespectedGameType(GameType) external {}

    // Minimal stubs for other required interface functions
    function anchorStateRegistry() external pure returns (IAnchorStateRegistry) {
        return IAnchorStateRegistry(address(0));
    }
    function __constructor__(uint256) external {}

    function respectedGameTypeUpdatedAt() external pure returns (uint64) {
        return 0;
    }
    function upgrade(IAnchorStateRegistry) external {}

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
    function finalizeWithdrawalTransaction(bytes32) external {}
    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory) external {}
    function finalizeWithdrawalTransactionExternalProof(bytes32, address) external {}
    function finalizeWithdrawalTransactionExternalProof(Types.WithdrawalTransaction memory, address) external {}

    function finalizedWithdrawals(bytes32) external pure returns (bool) {
        return false;
    }
    function initialize(bool, address[] calldata) external {}

    function initVersion() external pure returns (uint8) {
        return 0;
    }

    function minimumGasLimit(uint64) external pure returns (uint64) {
        return 0;
    }

    function numProofSubmitters(bytes32) external pure returns (uint256) {
        return 0;
    }

    function params() external pure returns (uint128, uint64, uint64) {
        return (0, 0, 0);
    }

    function proofSubmitters(bytes32, uint256) external pure returns (address) {
        return address(0);
    }
    function proveWithdrawalTransaction(bytes32, uint256, bytes32, bytes memory) external {}
    function proveWithdrawalTransaction(Types.WithdrawalTransaction memory, uint256, Types.OutputRootProof calldata, bytes[] calldata) external {}

    function proxyAdmin() external pure returns (IProxyAdmin) {
        return IProxyAdmin(address(0));
    }

    function proxyAdminOwner() external pure returns (address) {
        return address(0);
    }

    function ethLockbox() external pure returns (IETHLockbox) {
        return IETHLockbox(address(0));
    }

    function disputeGameBlacklist(IDisputeGame) external pure returns (bool) {
        return false;
    }
    function depositTransaction(address, uint256, uint64, bool, bytes memory) external payable {}
    function initialize(ISystemConfig, IAnchorStateRegistry) external {}
}
