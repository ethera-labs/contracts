// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ISemver } from "@optimism/interfaces/universal/ISemver.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { IComposePortal } from "./IComposePortal.sol";

interface IComposeERC20Lockbox is ISemver {
    error ERC20Lockbox_Paused();
    error ERC20Lockbox_Unauthorized();
    error ERC20Lockbox_InsufficientBalance();
    error ERC20Lockbox_ZeroAmount();
    error ERC20Lockbox_ZeroAddress();
    error ERC20Lockbox_NotInFinalize();

    event ERC20Locked(address indexed token, address indexed portal, uint256 amount);
    event ERC20Unlocked(address indexed token, address indexed portal, address indexed to, uint256 amount);
    event PortalAuthorized(IComposePortal indexed portal);
    event LockboxAuthorized(IComposeERC20Lockbox indexed lockbox);
    event LiquidityMigrated(address indexed token, IComposeERC20Lockbox indexed lockbox, uint256 amount);
    event LiquidityReceived(address indexed token, IComposeERC20Lockbox indexed lockbox, uint256 amount);

    function initialize(ISuperchainConfig _superChainConfig, IComposePortal[] calldata _portals) external;
    function superChainConfig() external view returns (ISuperchainConfig);
    function superchainConfig() external view returns (ISuperchainConfig);
    function paused() external view returns (bool);
    function totalDeposited(address token) external view returns (uint256);
    function authorizedPortals(IComposePortal) external view returns (bool);
    function authorizedLockboxes(IComposeERC20Lockbox) external view returns (bool);
    function lockERC20(address token, uint256 amount) external;
    function unlockERC20(address token, uint256 amount, address to) external;
    function authorizePortal(IComposePortal _portal) external;
    function authorizeLockbox(IComposeERC20Lockbox _lockbox) external;
    function migrateLiquidity(address token, IComposeERC20Lockbox _lockbox) external;
    function receiveLiquidity(address token, uint256 amount) external;
}
