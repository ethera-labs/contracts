// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ISemver } from "@optimism/interfaces/universal/ISemver.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";

interface IComposeERC20Lockbox is ISemver {
    error ERC20Lockbox_Paused();
    error ERC20Lockbox_Unauthorized();
    error ERC20Lockbox_InsufficientBalance();
    error ERC20Lockbox_ZeroAmount();
    error ERC20Lockbox_ZeroAddress();

    event ERC20Locked(address indexed token, address indexed bridge, uint256 amount);
    event ERC20Unlocked(address indexed token, address indexed bridge, address indexed to, uint256 amount);
    event BridgeAuthorized(address indexed bridge);
    event LockboxAuthorized(IComposeERC20Lockbox indexed lockbox);
    event LiquidityMigrated(address indexed token, IComposeERC20Lockbox indexed lockbox, uint256 amount);
    event LiquidityReceived(address indexed token, IComposeERC20Lockbox indexed lockbox, uint256 amount);

    function initialize(ISuperchainConfig _superChainConfig, address[] calldata _bridges) external;
    function superChainConfig() external view returns (ISuperchainConfig);
    function superchainConfig() external view returns (ISuperchainConfig);
    function paused() external view returns (bool);
    function totalDeposited(address token) external view returns (uint256);
    function authorizedBridges(address) external view returns (bool);
    function authorizedLockboxes(IComposeERC20Lockbox) external view returns (bool);
    function lockERC20(address token, address from, uint256 amount) external;
    function unlockERC20(address token, uint256 amount, address to) external;
    function authorizeBridge(address _bridge) external;
    function authorizeLockbox(IComposeERC20Lockbox _lockbox) external;
    function migrateLiquidity(address token, IComposeERC20Lockbox _lockbox) external;
    function receiveLiquidity(address token, uint256 amount) external;
}
