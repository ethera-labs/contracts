// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ProxyAdminOwnedBase} from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import {ReinitializableBase} from "@optimism/src/universal/ReinitializableBase.sol";

// Libraries
import {Constants} from "@optimism/src/libraries/Constants.sol";

// Interfaces
import {ISemver} from "@optimism/interfaces/universal/ISemver.sol";
import {IOptimismPortal2 as IOptimismPortal} from "@optimism/interfaces/L1/IOptimismPortal2.sol";
import {ISuperchainConfig} from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import {IETHLockbox} from "@optimism/interfaces/L1/IETHLockbox.sol";

/// @custom:proxied true
/// @title ComposeETHLockbox
/// @notice Manages ETH liquidity locking and unlocking for authorized OptimismPortals, enabling unified ETH liquidity
///         management across chains in the superchain cluster. Modified to use SuperchainConfig directly instead of
///         SystemConfig for simpler cluster-wide governance.
contract ComposeETHLockbox is ProxyAdminOwnedBase, Initializable, ReinitializableBase, ISemver {
    /// @notice Thrown when the lockbox is paused.
    error ETHLockbox_Paused();

    /// @notice Thrown when the caller is not authorized.
    error ETHLockbox_Unauthorized();

    /// @notice Thrown when the value to unlock is greater than the balance of the lockbox.
    error ETHLockbox_InsufficientBalance();

    /// @notice Thrown when attempting to unlock ETH from the lockbox through a withdrawal transaction.
    error ETHLockbox_NoWithdrawalTransactions();

    /// @notice Emitted when ETH is locked in the lockbox by an authorized portal.
    /// @param portal The address of the portal that locked the ETH.
    /// @param amount The amount of ETH locked.
    event ETHLocked(IOptimismPortal indexed portal, uint256 amount);

    /// @notice Emitted when ETH is unlocked from the lockbox by an authorized portal.
    /// @param portal The address of the portal that unlocked the ETH.
    /// @param amount The amount of ETH unlocked.
    event ETHUnlocked(IOptimismPortal indexed portal, uint256 amount);

    /// @notice Emitted when a portal is authorized to lock and unlock ETH.
    /// @param portal The address of the portal that was authorized.
    event PortalAuthorized(IOptimismPortal indexed portal);

    /// @notice Emitted when an ETH lockbox is authorized to migrate its liquidity to the current ETH lockbox.
    /// @param lockbox The address of the ETH lockbox that was authorized.
    event LockboxAuthorized(IETHLockbox indexed lockbox);

    /// @notice Emitted when ETH liquidity is migrated from the current ETH lockbox to another.
    /// @param lockbox The address of the ETH lockbox that was migrated.
    event LiquidityMigrated(IETHLockbox indexed lockbox, uint256 amount);

    /// @notice Emitted when ETH liquidity is received during an authorized lockbox migration.
    /// @param lockbox The address of the ETH lockbox that received the liquidity.
    /// @param amount The amount of ETH received.
    event LiquidityReceived(IETHLockbox indexed lockbox, uint256 amount);

    /// @notice The address of the SuperchainConfig contract (used instead of SystemConfig).
    ISuperchainConfig public superChainConfig;

    /// @notice Mapping of authorized portals.
    mapping(IOptimismPortal => bool) public authorizedPortals;

    /// @notice Mapping of authorized lockboxes.
    mapping(IETHLockbox => bool) public authorizedLockboxes;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-compose
    function version() public view virtual returns (string memory) {
        return "1.0.0-compose";
    }

    /// @notice Constructs the ComposeETHLockbox contract.
    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _superChainConfig The address of the SuperchainConfig contract.
    /// @param _portals The addresses of the portals to authorize.
    /// @dev Note: Multiple chains can share a ComposeETHLockbox contract. All portals should point to the
    ///      same SuperchainConfig for cluster-wide pause control.
    function initialize(ISuperchainConfig _superChainConfig, IOptimismPortal[] calldata _portals) external reinitializer(initVersion()) {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // Now perform initialization logic.
        superChainConfig = _superChainConfig;
        for (uint256 i; i < _portals.length; i++) {
            _authorizePortal(_portals[i]);
        }
    }

    /// @notice Getter for the current paused status.
    /// @dev Checks both global pause and lockbox-specific pause.
    function paused() public view returns (bool) {
        // Check both global and lockbox-specific pauses
        if (superChainConfig.paused(address(0)) || superChainConfig.paused(address(this))) {
            return true;
        }

        return false;
    }

    /// @notice Returns the SuperchainConfig contract.
    /// @return ISuperchainConfig The SuperchainConfig contract.
    function superchainConfig() public view returns (ISuperchainConfig) {
        return superChainConfig;
    }

    /// @notice Authorizes a portal to lock and unlock ETH.
    /// @param _portal The address of the portal to authorize.
    function authorizePortal(IOptimismPortal _portal) external {
        // Check that this transaction is coming from the ProxyAdmin owner.
        _assertOnlyProxyAdminOwner();

        // Authorize the portal.
        _authorizePortal(_portal);
    }

    /// @notice Receives the ETH liquidity migrated from an authorized lockbox.
    function receiveLiquidity() external payable {
        // Check that the sender is authorized to trigger this function.
        IETHLockbox sender = IETHLockbox(payable(msg.sender));
        if (!authorizedLockboxes[sender]) revert ETHLockbox_Unauthorized();

        // Emit the event.
        emit LiquidityReceived(sender, msg.value);
    }

    /// @notice Locks ETH in the lockbox.
    ///         Called by an authorized portal on a deposit to lock the ETH value.
    function lockETH() external payable {
        // Check that the sender is authorized to trigger this function.
        IOptimismPortal sender = IOptimismPortal(payable(msg.sender));
        if (!authorizedPortals[sender]) revert ETHLockbox_Unauthorized();

        // Emit the event.
        emit ETHLocked(sender, msg.value);
    }

    /// @notice Unlocks ETH from the lockbox.
    ///         Called by an authorized portal when finalizing a withdrawal that requires ETH.
    ///         Cannot be called if the lockbox is paused.
    /// @param _value The amount of ETH to unlock.
    function unlockETH(uint256 _value) external {
        // Unlocks are blocked when paused, locks are not.
        if (paused()) revert ETHLockbox_Paused();

        // Check that the sender is authorized to trigger this function.
        IOptimismPortal sender = IOptimismPortal(payable(msg.sender));
        if (!authorizedPortals[sender]) revert ETHLockbox_Unauthorized();

        // Check that we have enough balance to process the unlock.
        if (_value > address(this).balance) revert ETHLockbox_InsufficientBalance();

        // Check that the sender is not executing a withdrawal transaction.
        if (sender.l2Sender() != Constants.DEFAULT_L2_SENDER) {
            revert ETHLockbox_NoWithdrawalTransactions();
        }

        // Using donateETH to avoid triggering a deposit.
        sender.donateETH{value: _value}();

        // Emit the event.
        emit ETHUnlocked(sender, _value);
    }

    /// @notice Authorizes another lockbox to receive liquidity from this lockbox.
    /// @dev    Must be called atomically with `migrateLiquidity()` in the same transaction batch.
    /// @param _lockbox The address of the lockbox to authorize.
    function authorizeLockbox(IETHLockbox _lockbox) external {
        // Check that this transaction is coming from the ProxyAdmin owner.
        _assertOnlyProxyAdminOwner();

        // Check that the lockbox has the same proxy admin owner.
        // NOTE: Disabled for multi-owner architecture where Compose and rollup have different ProxyAdmin owners
        // In multi-lockbox scenarios, authorization is explicit and controlled by ProxyAdmin owner
        // _assertSharedProxyAdminOwner(address(_lockbox));

        // Authorize the lockbox.
        authorizedLockboxes[_lockbox] = true;

        // Emit the event.
        emit LockboxAuthorized(_lockbox);
    }

    /// @notice Migrates liquidity from the current ETH lockbox to another.
    /// @dev    Must be called atomically with `OptimismPortal.migrateToSuperRoots()` in the same
    ///         transaction batch, or otherwise the OptimismPortal may not be able to unlock ETH
    ///         from the ETHLockbox on finalized withdrawals.
    /// @param _lockbox The address of the ETH lockbox to migrate liquidity to.
    function migrateLiquidity(IETHLockbox _lockbox) external {
        // Check that this transaction is coming from the ProxyAdmin owner.
        _assertOnlyProxyAdminOwner();

        // Check that the lockbox has the same proxy admin owner.
        // NOTE: Disabled for multi-owner architecture where Compose and rollup have different ProxyAdmin owners
        // Security is ensured by explicit authorization via ProxyAdmin owner
        // _assertSharedProxyAdminOwner(address(_lockbox));

        // Receive the liquidity.
        uint256 balance = address(this).balance;
        IETHLockbox(_lockbox).receiveLiquidity{value: balance}();

        // Emit the event.
        emit LiquidityMigrated(_lockbox, balance);
    }

    /// @notice Authorizes a portal to lock and unlock ETH.
    /// @param _portal The address of the portal to authorize.
    function _authorizePortal(IOptimismPortal _portal) internal {
        // Check that the portal has the same proxy admin owner.
        // NOTE: Disabled for multi-owner architecture where Compose and rollup have different ProxyAdmin owners
        // _assertSharedProxyAdminOwner(address(_portal));

        // Authorize the portal.
        authorizedPortals[_portal] = true;

        // Emit the event.
        emit PortalAuthorized(_portal);
    }
}
