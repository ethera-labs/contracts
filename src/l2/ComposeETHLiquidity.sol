// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IETHLiquidity } from "src/l2/interfaces/external/IETHLiquidity.sol";

/// @title ComposeETHLiquidity
/// @notice Minimal ETHLiquidity-shaped pool for the Compose L2↔L2 bridge on chains where the
///         canonical `0x4200…0025` predeploy's `onlySuperchainETHBridge` gate blocks our bridge.
///         Interface-compatible drop-in: same `burn()`/`mint(uint256)`/`fund()` surface, so the
///         bridge code is unchanged — only the constructor arg flips.
///
///         Differences vs the OP predeploy:
///           - No pre-minted `type(uint248).max` genesis balance. Pool starts at 0 and is seeded
///             via `fund()` calls or plain `receive()`.
///           - Access list: owner-managed `authorizedBridges` mapping.
contract ComposeETHLiquidity is IETHLiquidity {
    address public immutable owner;
    mapping(address => bool) public authorizedBridges;

    error ZeroAddress();
    error TransferFailed();

    event BridgeAuthorized(address indexed bridge);
    event BridgeRevoked(address indexed bridge);

    modifier onlyBridge() {
        if (!authorizedBridges[msg.sender]) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    /// @notice Accept ETH donations / seed without an auth check.
    receive() external payable {
        emit LiquidityFunded(msg.sender, msg.value);
    }

    /// @notice Authorize a bridge to call `burn`/`mint`.
    function authorizeBridge(address _bridge) external onlyOwner {
        if (_bridge == address(0)) revert ZeroAddress();
        authorizedBridges[_bridge] = true;
        emit BridgeAuthorized(_bridge);
    }

    /// @notice Revoke a bridge.
    function revokeBridge(address _bridge) external onlyOwner {
        authorizedBridges[_bridge] = false;
        emit BridgeRevoked(_bridge);
    }

    /// @notice Bridge sends ETH in (locks liquidity).
    function burn() external payable onlyBridge {
        if (msg.value == 0) revert InvalidAmount();
        emit LiquidityBurned(msg.sender, msg.value);
    }

    /// @notice Bridge releases ETH out (unlocks liquidity to the caller).
    function mint(uint256 _amount) external onlyBridge {
        if (_amount == 0) revert InvalidAmount();
        if (address(this).balance < _amount) revert InvalidAmount();
        emit LiquidityMinted(msg.sender, _amount);
        (bool ok, ) = msg.sender.call{ value: _amount }("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Permissionless pool seeding.
    function fund() external payable {
        if (msg.value == 0) revert InvalidAmount();
        emit LiquidityFunded(msg.sender, msg.value);
    }

    function version() external pure returns (string memory) {
        return "1.0.0-compose";
    }

    /// @dev Required by the IETHLiquidity shape; unused at runtime.
    function __constructor__() external pure { }
}
