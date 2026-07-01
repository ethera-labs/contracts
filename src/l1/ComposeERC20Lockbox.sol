// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ProxyAdminOwnedBase} from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import {ReinitializableBase} from "@optimism/src/universal/ReinitializableBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Constants} from "@optimism/src/libraries/Constants.sol";
import {ISuperchainConfig} from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import {IComposeERC20Lockbox} from "src/l1/interfaces/IComposeERC20Lockbox.sol";
import {IComposePortal} from "src/l1/interfaces/IComposePortal.sol";

/// @custom:proxied true
/// @title ComposeERC20Lockbox
/// @notice Shared ERC20 escrow for the Compose universal bridge. Authorized ComposePortals are the
///         sole callers of lock/unlock. Portals push tokens into this contract before calling
///         `lockERC20`; unlocks pull from the lockbox balance. Complete per-token accounting
///         isolation: a malicious token can only break its own accounting.
contract ComposeERC20Lockbox is ProxyAdminOwnedBase, Initializable, ReinitializableBase, IComposeERC20Lockbox {
    using SafeERC20 for IERC20;

    /// @notice The SuperchainConfig used for cluster-wide pause control.
    ISuperchainConfig public superChainConfig;

    /// @notice Authorized ComposePortals.
    mapping(IComposePortal => bool) public authorizedPortals;

    /// @notice Per-token deposited accounting. Must always be <= balanceOf(this).
    mapping(address => uint256) public totalDeposited;

    /// @notice Authorized peer lockboxes (for migrations).
    mapping(IComposeERC20Lockbox => bool) public authorizedLockboxes;

    /// @notice Semantic version.
    /// @custom:semver 2.0.0-compose
    function version() public view virtual returns (string memory) {
        return "1.0.0-compose";
    }

    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _superChainConfig The SuperchainConfig contract for cluster-wide pause control.
    /// @param _portals          Portals to authorize at init.
    function initialize(ISuperchainConfig _superChainConfig, IComposePortal[] calldata _portals) external reinitializer(initVersion()) {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        superChainConfig = _superChainConfig;
        for (uint256 i; i < _portals.length; i++) {
            _authorizePortal(_portals[i]);
        }
    }

    /// @notice Returns whether the lockbox is paused (global or lockbox-specific).
    function paused() public view returns (bool) {
        return superChainConfig.paused(address(0)) || superChainConfig.paused(address(this));
    }

    /// @notice Returns the SuperchainConfig contract.
    function superchainConfig() public view returns (ISuperchainConfig) {
        return superChainConfig;
    }

    /// @notice Authorizes a ComposePortal. Only callable by the ProxyAdmin owner.
    function authorizePortal(IComposePortal _portal) external {
        _assertOnlyProxyAdminOwner();
        _authorizePortal(_portal);
    }

    /// @notice Locks ERC20 tokens. Portal MUST transfer `_amount` of `_token` to this contract
    ///         before calling — the balance-invariant check enforces that.
    /// @param _token  Token being locked.
    /// @param _amount Amount being locked.
    function lockERC20(address _token, uint256 _amount) external {
        if (_amount == 0) revert ERC20Lockbox_ZeroAmount();
        if (_token == address(0)) revert ERC20Lockbox_ZeroAddress();
        if (!authorizedPortals[IComposePortal(msg.sender)]) revert ERC20Lockbox_Unauthorized();

        totalDeposited[_token] += _amount;

        // Enforce the deposit invariant: portal must have pushed tokens before calling.
        if (IERC20(_token).balanceOf(address(this)) < totalDeposited[_token]) {
            revert ERC20Lockbox_InsufficientBalance();
        }

        emit ERC20Locked(_token, msg.sender, _amount);
    }

    /// @notice Unlocks ERC20 tokens to `_to`. Portal-only. Blocked when paused. Must be called
    ///         from within a withdrawal finalize context (portal's l2Sender already set by the
    ///         parent OptimismPortal2 before calling the withdrawal target).
    /// @param _token  Token being unlocked.
    /// @param _amount Amount being unlocked.
    /// @param _to     Recipient of unlocked tokens.
    function unlockERC20(address _token, uint256 _amount, address _to) external {
        if (paused()) revert ERC20Lockbox_Paused();
        if (_amount == 0) revert ERC20Lockbox_ZeroAmount();
        if (_token == address(0) || _to == address(0)) revert ERC20Lockbox_ZeroAddress();

        IComposePortal sender = IComposePortal(msg.sender);
        if (!authorizedPortals[sender]) revert ERC20Lockbox_Unauthorized();
        if (sender.l2Sender() == Constants.DEFAULT_L2_SENDER) revert ERC20Lockbox_NotInFinalize();

        if (totalDeposited[_token] < _amount) revert ERC20Lockbox_InsufficientBalance();
        if (IERC20(_token).balanceOf(address(this)) < _amount) revert ERC20Lockbox_InsufficientBalance();

        totalDeposited[_token] -= _amount;
        IERC20(_token).safeTransfer(_to, _amount);

        emit ERC20Unlocked(_token, msg.sender, _to, _amount);
    }

    /// @notice Authorizes a peer lockbox for migration. ProxyAdmin-owner only.
    function authorizeLockbox(IComposeERC20Lockbox _lockbox) external {
        _assertOnlyProxyAdminOwner();
        authorizedLockboxes[_lockbox] = true;
        emit LockboxAuthorized(_lockbox);
    }

    /// @notice Receives token liquidity from an authorized peer lockbox during migration.
    function receiveLiquidity(address _token, uint256 _amount) external {
        IComposeERC20Lockbox senderLb = IComposeERC20Lockbox(msg.sender);
        if (!authorizedLockboxes[senderLb]) revert ERC20Lockbox_Unauthorized();
        emit LiquidityReceived(_token, senderLb, _amount);
    }

    /// @notice Migrates all balance of `_token` to another lockbox.
    function migrateLiquidity(address _token, IComposeERC20Lockbox _lockbox) external {
        _assertOnlyProxyAdminOwner();
        uint256 bal = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(_lockbox), bal);
        _lockbox.receiveLiquidity(_token, bal);
        emit LiquidityMigrated(_token, _lockbox, bal);
    }

    function _authorizePortal(IComposePortal _portal) internal {
        if (address(_portal) == address(0)) revert ERC20Lockbox_ZeroAddress();
        authorizedPortals[_portal] = true;
        emit PortalAuthorized(_portal);
    }
}
