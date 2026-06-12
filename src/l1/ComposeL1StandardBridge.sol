// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProxyAdminOwnedBase} from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import {ReinitializableBase} from "@optimism/src/universal/ReinitializableBase.sol";
import {Predeploys} from "@optimism/src/libraries/Predeploys.sol";
import {SafeCall} from "@optimism/src/libraries/SafeCall.sol";

import {ICrossDomainMessenger} from "@optimism/interfaces/universal/ICrossDomainMessenger.sol";
import {ILegacyMintableERC20} from "@optimism/interfaces/legacy/ILegacyMintableERC20.sol";
import {IOptimismMintableERC20} from "@optimism/interfaces/universal/IOptimismMintableERC20.sol";
import {ISemver} from "@optimism/interfaces/universal/ISemver.sol";
import {IStandardBridge} from "@optimism/interfaces/universal/IStandardBridge.sol";
import {ISystemConfig} from "@optimism/interfaces/L1/ISystemConfig.sol";
import {ISuperchainConfig} from "@optimism/interfaces/L1/ISuperchainConfig.sol";

/// @custom:proxied true
/// @title ComposeL1StandardBridge
/// @notice Storage-compatible L1StandardBridge replacement that blocks all new legacy deposits.
///         Withdrawal/finalization paths are preserved for already-existing legacy bridge state.
contract ComposeL1StandardBridge is Initializable, ProxyAdminOwnedBase, ReinitializableBase, ISemver {
    using SafeERC20 for IERC20;

    /// @custom:legacy
    /// @notice Emitted whenever a deposit of ETH from L1 into L2 is initiated.
    event ETHDepositInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Emitted whenever a withdrawal of ETH from L2 to L1 is finalized.
    event ETHWithdrawalFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 deposit is initiated.
    event ERC20DepositInitiated(address indexed l1Token, address indexed l2Token, address indexed from, address to, uint256 amount, bytes extraData);

    /// @custom:legacy
    /// @notice Emitted whenever an ERC20 withdrawal is finalized.
    event ERC20WithdrawalFinalized(address indexed l1Token, address indexed l2Token, address indexed from, address to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ETH bridge is finalized on this chain.
    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    /// @notice Emitted when an ERC20 bridge is finalized on this chain.
    event ERC20BridgeFinalized(address indexed localToken, address indexed remoteToken, address indexed from, address to, uint256 amount, bytes extraData);

    /// @notice Thrown by all post-upgrade legacy deposit entry points.
    error ComposeL1StandardBridge_DepositsDisabled();

    /// @notice Thrown when caller is not the remote bridge through the canonical messenger.
    error ComposeL1StandardBridge_NotFromOtherBridge();

    /// @notice Thrown when the bridge is paused.
    error ComposeL1StandardBridge_Paused();

    /// @notice Thrown when ETH value does not match the finalize amount.
    error ComposeL1StandardBridge_ETHValueMismatch();

    /// @notice Thrown when ETH is finalized to an unsafe target.
    error ComposeL1StandardBridge_BadETHTarget();

    /// @notice Thrown when an ETH finalize transfer fails.
    error ComposeL1StandardBridge_ETHTransferFailed();

    /// @notice Thrown when an OptimismMintableERC20 remote token pair is invalid.
    error ComposeL1StandardBridge_WrongRemoteToken();

    /// @notice Semantic version.
    /// @custom:semver 2.7.0-compose-blocked
    string public constant version = "2.7.0-compose-blocked";

    // Storage copied from StandardBridge. Do not reorder.
    bytes30 private spacer_0_2_30;
    address private spacer_1_0_20;
    mapping(address => mapping(address => uint256)) public deposits;
    ICrossDomainMessenger public messenger;
    IStandardBridge public otherBridge;
    uint256[45] private __gap;

    // Storage copied from L1StandardBridge. Do not reorder.
    address private spacer_50_0_20;
    address private spacer_51_0_20;
    ISystemConfig public systemConfig;

    constructor() ReinitializableBase(3) {
        _disableInitializers();
    }

    /// @notice Initializer for fresh deployments. Existing upgraded proxies already hold these values.
    function initialize(ICrossDomainMessenger _messenger, ISystemConfig _systemConfig) external reinitializer(initVersion()) {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        systemConfig = _systemConfig;
        messenger = _messenger;
        otherBridge = IStandardBridge(payable(Predeploys.L2_STANDARD_BRIDGE));
    }

    /// @notice Upgrade hook matching the upstream L1StandardBridge signature.
    function upgrade(ISystemConfig _systemConfig) external reinitializer(initVersion()) {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        systemConfig = _systemConfig;
    }

    /// @notice Returns whether the bridge is paused.
    function paused() public view returns (bool) {
        return systemConfig.paused();
    }

    /// @notice Returns the SuperchainConfig contract.
    function superchainConfig() public view returns (ISuperchainConfig) {
        return systemConfig.superchainConfig();
    }

    /// @custom:legacy
    function MESSENGER() external view returns (ICrossDomainMessenger) {
        return messenger;
    }

    /// @custom:legacy
    function OTHER_BRIDGE() external view returns (IStandardBridge) {
        return otherBridge;
    }

    /// @custom:legacy
    function l2TokenBridge() external view returns (address) {
        return address(otherBridge);
    }

    receive() external payable {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function bridgeETH(uint32, bytes calldata) external payable {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function bridgeETHTo(address, uint32, bytes calldata) external payable {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function depositETH(uint32, bytes calldata) external payable {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function depositETHTo(address, uint32, bytes calldata) external payable {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function bridgeERC20(address, address, uint256, uint32, bytes calldata) external {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function bridgeERC20To(address, address, address, uint256, uint32, bytes calldata) external {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function depositERC20(address, address, uint256, uint32, bytes calldata) external {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    function depositERC20To(address, address, address, uint256, uint32, bytes calldata) external {
        revert ComposeL1StandardBridge_DepositsDisabled();
    }

    /// @notice Finalizes an ETH bridge on this chain.
    function finalizeBridgeETH(address _from, address _to, uint256 _amount, bytes calldata _extraData) public payable {
        _assertOnlyOtherBridge();
        if (paused()) revert ComposeL1StandardBridge_Paused();
        if (msg.value != _amount) revert ComposeL1StandardBridge_ETHValueMismatch();
        if (_to == address(this) || _to == address(messenger)) revert ComposeL1StandardBridge_BadETHTarget();

        emit ETHWithdrawalFinalized(_from, _to, _amount, _extraData);
        emit ETHBridgeFinalized(_from, _to, _amount, _extraData);

        bool success = SafeCall.call(_to, gasleft(), _amount, hex"");
        if (!success) revert ComposeL1StandardBridge_ETHTransferFailed();
    }

    /// @custom:legacy
    function finalizeETHWithdrawal(address _from, address _to, uint256 _amount, bytes calldata _extraData) external payable {
        finalizeBridgeETH(_from, _to, _amount, _extraData);
    }

    /// @notice Finalizes an ERC20 bridge on this chain.
    function finalizeBridgeERC20(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes calldata _extraData) public {
        _assertOnlyOtherBridge();
        if (paused()) revert ComposeL1StandardBridge_Paused();

        if (_isOptimismMintableERC20(_localToken)) {
            if (!_isCorrectTokenPair(_localToken, _remoteToken)) revert ComposeL1StandardBridge_WrongRemoteToken();
            IOptimismMintableERC20(_localToken).mint(_to, _amount);
        } else {
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] - _amount;
            IERC20(_localToken).safeTransfer(_to, _amount);
        }

        emit ERC20WithdrawalFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @custom:legacy
    function finalizeERC20Withdrawal(address _l1Token, address _l2Token, address _from, address _to, uint256 _amount, bytes calldata _extraData) external {
        finalizeBridgeERC20(_l1Token, _l2Token, _from, _to, _amount, _extraData);
    }

    function _assertOnlyOtherBridge() internal view {
        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != address(otherBridge)) {
            revert ComposeL1StandardBridge_NotFromOtherBridge();
        }
    }

    function _isOptimismMintableERC20(address _token) internal view returns (bool) {
        return ERC165Checker.supportsInterface(_token, type(ILegacyMintableERC20).interfaceId)
            || ERC165Checker.supportsInterface(_token, type(IOptimismMintableERC20).interfaceId);
    }

    function _isCorrectTokenPair(address _mintableToken, address _otherToken) internal view returns (bool) {
        if (ERC165Checker.supportsInterface(_mintableToken, type(ILegacyMintableERC20).interfaceId)) {
            return _otherToken == ILegacyMintableERC20(_mintableToken).l1Token();
        }
        return _otherToken == IOptimismMintableERC20(_mintableToken).remoteToken();
    }
}
