// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

interface ICETFactory {
    error DeploymentFailed();
    error OnlyBridge();
    error OnlyDeployer();
    error BridgeAlreadySet();
    error ZeroAddress();

    function computeSalt(address remoteAsset, uint256 remoteChainID) external pure returns (bytes32);
    function predictAddress(
        address remoteAsset,
        uint256 remoteChainID,
        uint8 decimals,
        string memory name,
        string memory symbol
    ) external view returns (address);
    function deployIfAbsent(
        address remoteAsset,
        uint256 remoteChainID,
        uint8 decimals,
        string calldata name,
        string calldata symbol
    ) external returns (address deployed);
}