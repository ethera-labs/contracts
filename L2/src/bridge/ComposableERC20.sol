// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC7802 } from "@ssv/src/bridge/interfaces/IERC7802.sol";
import { IComposableERC20 } from "@ssv/src/bridge/interfaces/IComposableERC20.sol";

/// @title ComposableERC20
/// @notice ERC7802-compliant CET. Constructor takes only identity args (remoteAsset,
///         remoteChainID, bridge) so that CREATE2 address depends on those alone.
///         Human-readable metadata (name/symbol/decimals) is set post-deploy via
///         `initializeMetadata`, one-shot, owner-gated.
contract ComposableERC20 is ERC20, IERC7802, IComposableERC20 {
    address public immutable override remoteAsset;
    uint256 public immutable override remoteChainID;

    address public immutable owner;
    CetType public immutable override cetType;
    mapping(address => bool) public authorizedBridges;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    bool private _metadataInitialized;

    constructor(
        address _remoteAsset,
        uint256 _remoteChainID,
        address _bridge
    ) ERC20("", "") {
        remoteAsset = _remoteAsset;
        remoteChainID = _remoteChainID;
        owner = msg.sender;
        cetType = (_remoteAsset == address(this) && _remoteChainID == block.chainid)
            ? CetType.CORE
            : CetType.WRAPPED;
        authorizedBridges[_bridge] = true;
        emit BridgeAuthorized(_bridge);
    }

    /// @notice One-shot metadata initializer. Owner-gated (factory).
    function initializeMetadata(string calldata name_, string calldata symbol_, uint8 decimals_) external {
        if (msg.sender != owner) revert Unauthorized();
        if (_metadataInitialized) revert AlreadyInitialized();
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _metadataInitialized = true;
    }

    function authorizeBridge(address _bridge) external {
        if (msg.sender != owner) revert Unauthorized();
        authorizedBridges[_bridge] = true;
        emit BridgeAuthorized(_bridge);
    }

    function revokeBridge(address _bridge) external {
        if (msg.sender != owner) revert Unauthorized();
        authorizedBridges[_bridge] = false;
        emit BridgeRevoked(_bridge);
    }

    function crosschainMint(address to, uint256 amount) external override(IComposableERC20, IERC7802) {
        _onlyBridge();
        _mint(to, amount);
        emit CrosschainMint(to, amount, msg.sender);
    }

    function crosschainBurn(address from, uint256 amount) external override(IComposableERC20, IERC7802) {
        _onlyBridge();
        _burn(from, amount);
        emit CrosschainBurn(from, amount, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IComposableERC20).interfaceId || interfaceId == type(IERC7802).interfaceId;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _onlyBridge() internal view {
        if (!authorizedBridges[msg.sender]) revert Unauthorized();
    }
}
