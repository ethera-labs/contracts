// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.0;

interface IComposableERC20 {
    /// @notice Storage struct for the BridgedComposeTokenERC20 metadata.
    struct BridgedComposeTokenERC20Metadata {
        /// @notice The ChainID where this token was originally minted.
        uint256 remoteChainID;
        /// @notice Address of the corresponding version of this token on the remote chain.
        address remoteAsset;
        /// @notice Name of the token
        string name;
        /// @notice Symbol of the token
        string symbol;
        /// @notice Decimals of the token
        uint8 decimals;
    }

    error Unauthorized();
    error AlreadyInitialized();

    event BridgeAuthorized(address bridge);
    event BridgeRevoked(address bridge);

    /// @notice Address of canonical (L1) asset this CET represents
    function remoteAsset() external view returns (address);
    /// @notice ChainID of canonical chain
    function remoteChainID() external view returns (uint256);
    function crosschainMint(address _to, uint256 _amount) external;
    function crosschainBurn(address _to, uint256 _amount) external;
}