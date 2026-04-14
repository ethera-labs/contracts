// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Contracts
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ProxyAdminOwnedBase } from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import { ReinitializableBase } from "@optimism/src/universal/ReinitializableBase.sol";

// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCall } from "@optimism/src/libraries/SafeCall.sol";
import { EOA } from "@optimism/src/libraries/EOA.sol";

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ICrossDomainMessenger } from "@optimism/interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { ISemver } from "@optimism/interfaces/universal/ISemver.sol";
import { IComposeERC20Lockbox } from "./interfaces/IComposeERC20Lockbox.sol";

interface IComposePortalERC20 {
    function depositTransaction(
        address _localToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external;
    function unlockERC20(address _localToken, uint256 _amount, address _to) external;
}

/// @custom:proxied true
/// @title ComposeL1Bridge
/// @notice L1 side of the Compose universal shared bridge. L1 is canonical custody only:
///         every bridged ERC20 is escrowed in the shared ComposeERC20Lockbox via the
///         ComposePortal on deposit, and released through the same path on withdrawal.
///         No CET burn/mint logic on L1 — CET is an L2-only representation per spec.
///         ETH deposit flow is unchanged: bridge -> messenger -> portal -> ETHLockbox.
contract ComposeL1Bridge is Initializable, ProxyAdminOwnedBase, ReinitializableBase, ISemver {
    using SafeERC20 for IERC20;

    /// @notice The L2 gas limit set when ETH is deposited using the receive() function.
    uint32 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 200_000;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    ICrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    address public otherBridge;

    /// @notice SuperchainConfig used for cluster-wide pause control. Aligned with the lockboxes.
    ISuperchainConfig public superChainConfig;

    /// @notice Shared ERC20 lockbox that escrows tokens across all compose bridges.
    IComposeERC20Lockbox public erc20Lockbox;

    /// @notice ComposePortal that escrows ERC20 deposits and releases them on withdrawal.
    IComposePortalERC20 public composePortal;

    /// @notice Emitted when an ETH bridge is initiated to the other chain.
    event ETHBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ETH bridge is finalized on this chain.
    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ERC20 bridge is initiated to the other chain.
    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted when an ERC20 bridge is finalized on this chain.
    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:legacy
    /// @notice Mirrors `L1StandardBridge.ETHDepositInitiated` for indexer/SDK parity.
    event ETHDepositInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Mirrors `L1StandardBridge.ETHWithdrawalFinalized` for indexer/SDK parity.
    event ETHWithdrawalFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Mirrors `L1StandardBridge.ERC20DepositInitiated` for indexer/SDK parity.
    event ERC20DepositInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @custom:legacy
    /// @notice Mirrors `L1StandardBridge.ERC20WithdrawalFinalized` for indexer/SDK parity.
    event ERC20WithdrawalFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Thrown when a caller must be an EOA but isn't.
    error ComposeBridge_NotEOA();

    /// @notice Thrown when a caller must be the other bridge via the canonical messenger.
    error ComposeBridge_NotFromOtherBridge();

    /// @notice Thrown when the bridge is paused.
    error ComposeBridge_Paused();

    /// @notice Thrown when msg.value is non-zero on an ERC20 bridge call.
    error ComposeBridge_CannotSendValue();

    /// @notice Thrown when the ETH value sent doesn't match the declared amount.
    error ComposeBridge_ETHValueMismatch();

    /// @notice Thrown when ETH cannot be sent to the given target (self / messenger).
    error ComposeBridge_BadETHTarget();

    /// @notice Thrown when the low-level ETH transfer fails.
    error ComposeBridge_ETHTransferFailed();

    /// @notice Thrown when setOtherBridge is called after otherBridge is already set.
    error ComposeBridge_OtherBridgeAlreadySet();

    /// @notice Thrown when a required address argument is zero.
    error ComposeBridge_ZeroAddress();

    /// @notice Emitted when otherBridge is set post-initialization.
    event OtherBridgeSet(address indexed otherBridge);

    /// @notice Semantic version.
    /// @custom:semver 1.1.0-compose
    function version() public pure virtual returns (string memory) {
        return "1.1.0-compose";
    }

    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _messenger        Canonical L1 CrossDomainMessenger for this chain.
    /// @param _otherBridge      L2 compose bridge address.
    /// @param _superchainConfig SuperchainConfig contract for cluster-wide pause.
    /// @param _erc20Lockbox     Shared ERC20 lockbox.
    /// @param _composePortal    ComposePortal that escrows ERC20 deposits.
    function initialize(
        ICrossDomainMessenger _messenger,
        address _otherBridge,
        ISuperchainConfig _superchainConfig,
        IComposeERC20Lockbox _erc20Lockbox,
        IComposePortalERC20 _composePortal
    )
        external
        reinitializer(initVersion())
    {
        _assertOnlyProxyAdminOrProxyAdminOwner();

        messenger = _messenger;
        otherBridge = _otherBridge;
        superChainConfig = _superchainConfig;
        erc20Lockbox = _erc20Lockbox;
        composePortal = _composePortal;
    }

    /// @notice One-shot setter for `otherBridge`. Intended for deployments where the L2 bridge
    ///         address is not known at L1 bridge `initialize` time (pass `address(0)` then);
    ///         once set, cannot be changed. ProxyAdmin owner only.
    function setOtherBridge(address _otherBridge) external {
        _assertOnlyProxyAdminOwner();
        if (otherBridge != address(0)) revert ComposeBridge_OtherBridgeAlreadySet();
        if (_otherBridge == address(0)) revert ComposeBridge_ZeroAddress();
        otherBridge = _otherBridge;
        emit OtherBridgeSet(_otherBridge);
    }

    /// @notice Only allow EOAs to call the function. Prevents contract wallets from accidentally
    ///         bridging into an aliased address on the other chain.
    modifier onlyEOA() {
        if (!EOA.isSenderEOA()) revert ComposeBridge_NotEOA();
        _;
    }

    /// @notice Ensures the caller is the canonical messenger relaying a message from otherBridge.
    modifier onlyOtherBridge() {
        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != otherBridge) {
            revert ComposeBridge_NotFromOtherBridge();
        }
        _;
    }

    /// @notice Returns whether the bridge is paused. Mirrors lockbox semantics: global cluster
    ///         pause (address(0)) OR a bridge-specific pause (address(this)).
    function paused() public view returns (bool) {
        return superChainConfig.paused(address(0)) || superChainConfig.paused(address(this));
    }

    /// @notice Returns the SuperchainConfig contract.
    function superchainConfig() external view returns (ISuperchainConfig) {
        return superChainConfig;
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    receive() external payable onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, RECEIVE_DEFAULT_GAS_LIMIT, bytes(""));
    }

    /// @notice Sends ETH to the sender's address on the other chain.
    function bridgeETH(uint32 _minGasLimit, bytes calldata _extraData) external payable onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, _minGasLimit, _extraData);
    }

    /// @notice Sends ETH to a receiver's address on the other chain.
    function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable {
        _initiateBridgeETH(msg.sender, _to, msg.value, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to the sender's address on the other chain.
    function bridgeERC20(
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
        onlyEOA
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        external
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalizes an ETH bridge on this chain. Only callable via the canonical messenger
    ///         relaying from otherBridge.
    function finalizeBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        payable
        onlyOtherBridge
    {
        if (paused()) revert ComposeBridge_Paused();
        if (msg.value != _amount) revert ComposeBridge_ETHValueMismatch();
        if (_to == address(this) || _to == address(messenger)) revert ComposeBridge_BadETHTarget();

        emit ETHWithdrawalFinalized(_from, _to, _amount, _extraData);
        emit ETHBridgeFinalized(_from, _to, _amount, _extraData);

        bool success = SafeCall.call(_to, gasleft(), _amount, hex"");
        if (!success) revert ComposeBridge_ETHTransferFailed();
    }

    /// @notice Finalizes an ERC20 bridge on this chain. Always releases canonical L1 collateral
    ///         from the shared lockbox via the portal. Only callable via the canonical messenger
    ///         relaying from otherBridge.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        onlyOtherBridge
    {
        if (paused()) revert ComposeBridge_Paused();

        composePortal.unlockERC20(_localToken, _amount, _to);

        emit ERC20WithdrawalFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Initiates a bridge of ETH through the CrossDomainMessenger. ETH custody ends up
    ///         in the shared ETHLockbox via the portal's receive path.
    function _initiateBridgeETH(
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        if (msg.value != _amount) revert ComposeBridge_ETHValueMismatch();

        emit ETHDepositInitiated(_from, _to, _amount, _extraData);
        emit ETHBridgeInitiated(_from, _to, _amount, _extraData);

        messenger.sendMessage{ value: _amount }({
            _target: otherBridge,
            _message: abi.encodeWithSelector(this.finalizeBridgeETH.selector, _from, _to, _amount, _extraData),
            _minGasLimit: _minGasLimit
        });
    }

    /// @notice Initiates an ERC20 bridge. Always escrows the canonical L1 token in the shared
    ///         lockbox via the portal.
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
    {
        if (msg.value != 0) revert ComposeBridge_CannotSendValue();

        IERC20(_localToken).safeTransferFrom(_from, address(composePortal), _amount);
        composePortal.depositTransaction(_localToken, _from, _to, _amount, _extraData);

        emit ERC20DepositInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        emit ERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        // Pack canonical metadata for the L2 side so it can deploy a CET wrapper on first use
        // without needing an out-of-band registry. Layout: (name, symbol, decimals, userExtra).
        bytes memory packedExtra = abi.encode(
            IERC20Metadata(_localToken).name(),
            IERC20Metadata(_localToken).symbol(),
            IERC20Metadata(_localToken).decimals(),
            _extraData
        );

        messenger.sendMessage({
            _target: otherBridge,
            _message: abi.encodeWithSelector(
                // Args on the remote side reverse local/remote: the remote chain's view of the
                // local token IS the remoteToken we were handed here.
                ComposeL1Bridge.finalizeBridgeERC20.selector,
                _remoteToken,
                _localToken,
                _from,
                _to,
                _amount,
                packedExtra
            ),
            _minGasLimit: _minGasLimit
        });
    }
}
