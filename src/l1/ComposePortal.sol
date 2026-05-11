// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { OptimismPortalInterop } from "@optimism/src/L1/OptimismPortalInterop.sol";
import { Constants } from "@optimism/src/libraries/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IComposeERC20Lockbox } from "src/l1/interfaces/IComposeERC20Lockbox.sol";
import { IComposePortal } from "src/l1/interfaces/IComposePortal.sol";

/// @custom:proxied true
/// @title ComposePortal
/// @notice Extends OptimismPortalInterop with ERC20 custody via a shared ComposeERC20Lockbox.
///         Authorized L1 compose bridges call `depositTransaction` (ERC20 overload) to lock
///         non-CET tokens on deposit, and `unlockERC20` during withdrawal finalize to release
///         them. ETH custody remains handled by the parent's ETHLockbox integration.
/// @dev    Inherits OptimismPortalInterop (not OptimismPortal2) so that Super Root withdrawal
///         proofs keep working after the Compose impl swap. The parent's `superRootsActive` bool
///         sits at the exact storage slot previously reserved by OP2's `spacer_63_20_1`, so
///         chains migrated to Super Roots via `migrateToSuperRoots` retain that flag across the
///         upgrade without re-init.
contract ComposePortal is OptimismPortalInterop {
    using SafeERC20 for IERC20;

    /// @notice Shared ERC20 lockbox for non-CET tokens.
    /// @dev Appended after parent's last storage slot. Do not reorder.
    IComposeERC20Lockbox public erc20Lockbox;

    /// @notice Bridges authorized to lock deposits and trigger withdrawal unlocks.
    mapping(address => bool) public authorizedBridges;

    /// @notice Thrown when the caller is not an authorized L1 compose bridge.
    error ComposePortal_UnauthorizedBridge();

    /// @notice Thrown when an amount is zero.
    error ComposePortal_ZeroAmount();

    /// @notice Thrown when a required address is zero.
    error ComposePortal_ZeroAddress();

    /// @notice Thrown when `unlockERC20` is called outside a withdrawal finalize context.
    error ComposePortal_NotInFinalize();

    /// @notice Emitted when the ERC20 lockbox reference is (re)set.
    event ERC20LockboxSet(IComposeERC20Lockbox indexed lockbox);

    /// @notice Emitted when a bridge is authorized.
    event BridgeAuthorized(address indexed bridge);

    /// @notice Emitted when an ERC20 deposit is accepted and locked.
    event ERC20TransactionDeposited(
        address indexed localToken,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted when an ERC20 withdrawal is released during finalize.
    event ERC20TransactionUnlocked(
        address indexed localToken,
        address indexed to,
        uint256 amount,
        address indexed bridge
    );

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-compose
    function version() public pure override returns (string memory) {
        return "1.0.0-compose";
    }

    /// @param _proofMaturityDelaySeconds The proof maturity delay in seconds.
    constructor(uint256 _proofMaturityDelaySeconds) OptimismPortalInterop(_proofMaturityDelaySeconds) {
        // Parent constructor disables initializers and sets PROOF_MATURITY_DELAY_SECONDS.
    }

    /// @notice Compose-specific initializer. Hardcoded reinitializer(4) because the parent
    ///         OptimismPortal2 already consumes versions up to 3 via its `initialize`/`upgrade`.
    /// @param _erc20Lockbox Shared ERC20 lockbox.
    function initializeCompose(IComposeERC20Lockbox _erc20Lockbox) external reinitializer(4) {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        if (address(_erc20Lockbox) == address(0)) revert ComposePortal_ZeroAddress();
        erc20Lockbox = _erc20Lockbox;
        emit ERC20LockboxSet(_erc20Lockbox);
    }

    /// @notice Updates the ERC20 lockbox reference. ProxyAdmin-owner only.
    function setERC20Lockbox(IComposeERC20Lockbox _erc20Lockbox) external {
        _assertOnlyProxyAdminOwner();
        if (address(_erc20Lockbox) == address(0)) revert ComposePortal_ZeroAddress();
        erc20Lockbox = _erc20Lockbox;
        emit ERC20LockboxSet(_erc20Lockbox);
    }

    /// @notice Authorizes an L1 compose bridge.
    function authorizeBridge(address _bridge) external {
        _assertOnlyProxyAdminOwner();
        if (_bridge == address(0)) revert ComposePortal_ZeroAddress();
        authorizedBridges[_bridge] = true;
        emit BridgeAuthorized(_bridge);
    }

    /// @notice ERC20 deposit path. Called by the L1 compose bridge after it has transferred
    ///         `_amount` of `_localToken` to this portal. Portal forwards to the shared lockbox.
    /// @dev    This is an overload of the parent's ETH `depositTransaction`; Solidity resolves by
    ///         signature. Emits no `TransactionDeposited` — the bridge's `messenger.sendMessage`
    ///         drives L1→L2 derivation separately.
    /// @param _localToken Token being deposited.
    /// @param _from       L1 sender (for event/log provenance).
    /// @param _to         L2 recipient (for event/log provenance).
    /// @param _amount     Amount being deposited.
    /// @param _extraData  Arbitrary data for tooling.
    function depositTransaction(
        address _localToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
    {
        if (!authorizedBridges[msg.sender]) revert ComposePortal_UnauthorizedBridge();
        if (_amount == 0) revert ComposePortal_ZeroAmount();
        if (_localToken == address(0)) revert ComposePortal_ZeroAddress();

        IERC20(_localToken).safeTransfer(address(erc20Lockbox), _amount);
        erc20Lockbox.lockERC20(_localToken, _amount);

        emit ERC20TransactionDeposited(_localToken, _from, _to, _amount, _extraData);
    }

    /// @notice ERC20 withdrawal release. Called by an authorized L1 compose bridge while the
    ///         portal is inside a withdrawal finalize (l2Sender set by the parent's
    ///         finalizeWithdrawalTransaction before dispatching the target call).
    /// @param _localToken Token being released.
    /// @param _amount     Amount being released.
    /// @param _to         Recipient of the released tokens.
    function unlockERC20(address _localToken, uint256 _amount, address _to) external {
        if (!authorizedBridges[msg.sender]) revert ComposePortal_UnauthorizedBridge();
        if (_amount == 0) revert ComposePortal_ZeroAmount();
        if (_localToken == address(0) || _to == address(0)) revert ComposePortal_ZeroAddress();

        // Guard: must be inside parent's finalize call chain, where l2Sender was set to _tx.sender.
        if (l2Sender == Constants.DEFAULT_L2_SENDER) revert ComposePortal_NotInFinalize();

        erc20Lockbox.unlockERC20(_localToken, _amount, _to);

        emit ERC20TransactionUnlocked(_localToken, _to, _amount, msg.sender);
    }

    /// @notice Extends the parent's unsafe-target guard with the ERC20 lockbox, so a withdrawal
    ///         target cannot point at the lockbox directly.
    function _isUnsafeTarget(address _target) internal view override returns (bool) {
        return super._isUnsafeTarget(_target) || _target == address(erc20Lockbox);
    }
}
