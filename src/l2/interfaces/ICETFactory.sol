// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.0;

interface ICETFactory {
    error AlreadyInitialized();
    error DeploymentFailed();
    error OnlyBridge();
    error OnlyDeployer();
    error ZeroAddress();

    event BridgeAuthorized(address bridge);
    event BridgeRevoked(address bridge);

    function computeSalt(address remoteAsset, uint256 remoteChainID) external pure returns (bytes32);

    /// @notice Predicts deterministic CET address from canonical identity only. Metadata does
    ///         NOT affect the address.
    function predictAddress(address remoteAsset, uint256 remoteChainID) external view returns (address);

    /// @notice Deploys the CET if absent; then applies metadata via one-shot initializer.
    ///         Safe to call multiple times — idempotent past first deploy.
    function deployIfAbsent(
        address remoteAsset,
        uint256 remoteChainID,
        uint8 decimals,
        string calldata name,
        string calldata symbol
    ) external returns (address deployed);
}
