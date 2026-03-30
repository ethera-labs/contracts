// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ProxyAdminOwnedBase } from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "@optimism/src/universal/ReinitializableBase.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISemver } from "@optimism/interfaces/universal/ISemver.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";

/// @custom:proxied true
/// @title ComposeERC20Lockbox
/// @notice Manages ERC20 liquidity locking and unlocking for authorized L1StandardBridges, enabling unified ERC20
///         liquidity management across chains in the superchain cluster. This is the ERC20 counterpart to
///         ComposeETHLockbox — tokens deposited via any authorized bridge can be withdrawn from any other.
contract ComposeERC20Lockbox is ProxyAdminOwnedBase, Initializable, ReinitializableBase, IComposeERC20Lockbox {
    using SafeERC20 for IERC20;

    /// @notice The SuperchainConfig used for cluster-wide pause control.
    ISuperchainConfig public superChainConfig;

    /// @notice Mapping of authorized bridges.
    mapping(address => bool) public authorizedBridges;

    /// @notice Total deposited amount per token across all bridges.
    mapping(address => uint256) public totalDeposited;

    /// @notice Mapping of authorized lockboxes (for migration).
    mapping(IComposeERC20Lockbox => bool) public authorizedLockboxes;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-compose
    function version() public view virtual returns (string memory) {
        return "1.0.0-compose";
    }

    /// @notice Constructs the ComposeERC20Lockbox contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _superChainConfig The SuperchainConfig contract for cluster-wide pause control.
    /// @param _bridges          The bridges to authorize at initialization.
    function initialize(
        ISuperchainConfig _superChainConfig,
        address[] calldata _bridges
    )
        external
        reinitializer(initVersion())
    {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        superChainConfig = _superChainConfig;
        for (uint256 i; i < _bridges.length; i++) {
            _authorizeBridge(_bridges[i]);
        }
    }

    /// @notice Returns whether the lockbox is paused (global or lockbox-specific).
    function paused() public view returns (bool) {
        if (superChainConfig.paused(address(0)) || superChainConfig.paused(address(this))) {
            return true;
        }
        return false;
    }

    /// @notice Returns the SuperchainConfig contract.
    function superchainConfig() public view returns (ISuperchainConfig) {
        return superChainConfig;
    }

    /// @notice Authorizes a bridge. Only callable by the ProxyAdmin owner.
    /// @param _bridge The bridge to authorize.
    function authorizeBridge(address _bridge) external {
        _assertOnlyProxyAdminOwner();
        _authorizeBridge(_bridge);
    }

    /// @notice Locks ERC20 tokens into the lockbox.
    ///         Called by an authorized bridge when a user deposits tokens from L1 to L2.
    ///         The user must have approved this contract for `_amount` of `_token`.
    /// @param _token  The ERC20 token to lock.
    /// @param _from   The address to pull tokens from.
    /// @param _amount The amount to lock.
    function lockERC20(address _token, address _from, uint256 _amount) external {
        if (_amount == 0) {
            revert ERC20Lockbox_ZeroAmount();
        }
        if (_token == address(0) || _from == address(0)) {
            revert ERC20Lockbox_ZeroAddress();
        }
        if (!authorizedBridges[msg.sender]) {
            revert ERC20Lockbox_Unauthorized();
        }

        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        totalDeposited[_token] += _amount;

        emit ERC20Locked(_token, msg.sender, _amount);
    }

    /// @notice Unlocks ERC20 tokens from the lockbox.
    ///         Called by an authorized bridge when finalizing a withdrawal that requires ERC20 tokens.
    ///         Cannot be called if the lockbox is paused.
    /// @param _token  The ERC20 token to unlock.
    /// @param _amount The amount to unlock.
    /// @param _to     The recipient of the unlocked tokens.
    function unlockERC20(address _token, uint256 _amount, address _to) external {
        if (paused()) {
            revert ERC20Lockbox_Paused();
        }
        if (_amount == 0) {
            revert ERC20Lockbox_ZeroAmount();
        }
        if (_token == address(0) || _to == address(0)) {
            revert ERC20Lockbox_ZeroAddress();
        }
        if (!authorizedBridges[msg.sender]) {
            revert ERC20Lockbox_Unauthorized();
        }

        if (IERC20(_token).balanceOf(address(this)) < _amount) revert ERC20Lockbox_InsufficientBalance();

        totalDeposited[_token] -= _amount;
        IERC20(_token).safeTransfer(_to, _amount);

        emit ERC20Unlocked(_token, msg.sender, _to, _amount);
    }

    /// @notice Authorizes another lockbox for migration. Only callable by the ProxyAdmin owner.
    /// @param _lockbox The lockbox to authorize.
    function authorizeLockbox(IComposeERC20Lockbox _lockbox) external {
        _assertOnlyProxyAdminOwner();

        authorizedLockboxes[_lockbox] = true;

        emit LockboxAuthorized(_lockbox);
    }

    /// @notice Receives token liquidity from an authorized lockbox during migration.
    /// @param _token  The token being received.
    /// @param _amount The amount being received (must match the actual transfer).
    function receiveLiquidity(address _token, uint256 _amount) external {
        IComposeERC20Lockbox sender = IComposeERC20Lockbox(msg.sender);
        if (!authorizedLockboxes[sender]) {
            revert ERC20Lockbox_Unauthorized();
        }

        emit LiquidityReceived(_token, sender, _amount);
    }

    /// @notice Migrates all liquidity for a given token to another lockbox.
    /// @param _token   The token to migrate.
    /// @param _lockbox The destination lockbox.
    function migrateLiquidity(address _token, IComposeERC20Lockbox _lockbox) external {
        _assertOnlyProxyAdminOwner();

        uint256 balance = IERC20(_token).balanceOf(address(this));

        IERC20(_token).safeTransfer(address(_lockbox), balance);
        _lockbox.receiveLiquidity(_token, balance);

        emit LiquidityMigrated(_token, _lockbox, balance);
    }

    /// @notice Internal helper to authorize a bridge.
    /// @param _bridge The bridge to authorize.
    function _authorizeBridge(address _bridge) internal {
        if (_bridge == address(0)) revert ERC20Lockbox_ZeroAddress();

        authorizedBridges[_bridge] = true;

        emit BridgeAuthorized(_bridge);
    }
}
