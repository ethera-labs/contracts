// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.18;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {ICETFactory} from "src/l2/interfaces/ICETFactory.sol";
import {IComposableERC20} from "src/l2/interfaces/IComposableERC20.sol";

/// @notice Minimal L2 CrossDomainMessenger surface used here.
interface IL2CrossDomainMessenger {
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
    function xDomainMessageSender() external view returns (address);
}

/// @title L2ComposeBridge
/// @notice L2 side of the Compose universal bridge (L1↔L2 leg). Mirrors OP `L2StandardBridge`
///         surface but mints/burns `ComposableERC20` (CET) instead of `OptimismMintableERC20`.
///         L1 holds canonical custody; L2 only ever handles CET.
///
/// Deposit  (L1→L2): `finalizeBridgeERC20` decodes packed metadata from `_extraData`, ensures
///                   a CET at the predicted address for `(remoteToken=L1, l1ChainId)`, then
///                   `crosschainMint(to, amount)`.
/// Withdraw (L2→L1): `bridgeERC20*` burns CET then `L2XDM.sendMessage` to `L1ComposeBridge`.
/// ETH: native on both sides, forwarded via canonical XDM `{value}` path.
contract L2ComposeBridge is ReentrancyGuard {
    /// @notice Canonical L2 CrossDomainMessenger.
    IL2CrossDomainMessenger public immutable messenger;

    /// @notice CET factory. Must be at the same address on every chain this bridge is deployed on.
    ICETFactory public immutable cetFactory;

    /// @notice L1 chain id. Used as the CET `remoteChainID` for L1-originated assets.
    uint256 public immutable l1ChainId;

    /// @notice Owner of the bridge (for `setOtherBridge`).
    address public immutable owner;

    /// @notice Address of the L1ComposeBridge. One-shot set post-L1-deploy.
    address public otherBridge;

    event ETHBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ERC20BridgeInitiated(address indexed localToken, address indexed remoteToken, address indexed from, address to, uint256 amount, bytes extraData);
    event ERC20BridgeFinalized(address indexed localToken, address indexed remoteToken, address indexed from, address to, uint256 amount, bytes extraData);

    /// @custom:legacy
    event WithdrawalInitiated(address indexed l1Token, address indexed l2Token, address indexed from, address to, uint256 amount, bytes extraData);

    /// @custom:legacy
    event DepositFinalized(address indexed l1Token, address indexed l2Token, address indexed from, address to, uint256 amount, bytes extraData);

    event OtherBridgeSet(address indexed otherBridge);

    error NotEOA();
    error NotFromOtherBridge();
    error ZeroAddress();
    error NotCET();
    error LocalTokenMismatch();
    error NoETHSent();
    error ETHTransferFailed();
    error CannotSendValue();
    error ETHValueMismatch();
    error OnlyOwner();
    error OtherBridgeAlreadySet();

    constructor(address _messenger, address _cetFactory, uint256 _l1ChainId) {
        if (_messenger == address(0) || _cetFactory == address(0)) revert ZeroAddress();
        messenger = IL2CrossDomainMessenger(_messenger);
        cetFactory = ICETFactory(_cetFactory);
        l1ChainId = _l1ChainId;
        owner = msg.sender;
    }

    /// @notice One-shot setter for L1 bridge address. Owner only.
    function setOtherBridge(address _otherBridge) external {
        if (msg.sender != owner) revert OnlyOwner();
        if (otherBridge != address(0)) revert OtherBridgeAlreadySet();
        if (_otherBridge == address(0)) revert ZeroAddress();
        otherBridge = _otherBridge;
        emit OtherBridgeSet(_otherBridge);
    }

    modifier onlyEOA() {
        if (msg.sender != tx.origin) revert NotEOA();
        _;
    }

    modifier onlyOtherBridge() {
        if (msg.sender != address(messenger) || messenger.xDomainMessageSender() != otherBridge) {
            revert NotFromOtherBridge();
        }
        _;
    }

    receive() external payable onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, 200_000, bytes(""));
    }

    function bridgeETH(uint32 _minGasLimit, bytes calldata _extraData) external payable onlyEOA {
        _initiateBridgeETH(msg.sender, msg.sender, msg.value, _minGasLimit, _extraData);
    }

    function bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData) external payable {
        _initiateBridgeETH(msg.sender, _to, msg.value, _minGasLimit, _extraData);
    }

    function bridgeERC20(address _localToken, address _remoteToken, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external onlyEOA {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    function bridgeERC20To(address _localToken, address _remoteToken, address _to, uint256 _amount, uint32 _minGasLimit, bytes calldata _extraData) external {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalize ETH deposit from L1. Forwards `msg.value` to `_to`.
    function finalizeBridgeETH(address _from, address _to, uint256 _amount, bytes calldata _extraData) external payable onlyOtherBridge nonReentrant {
        if (msg.value != _amount) revert ETHValueMismatch();
        if (_to == address(this) || _to == address(messenger)) revert ZeroAddress();

        emit DepositFinalized(address(0), address(0), _from, _to, _amount, _extraData);
        emit ETHBridgeFinalized(_from, _to, _amount, _extraData);

        (bool ok,) = _to.call{value: _amount}("");
        if (!ok) revert ETHTransferFailed();
    }

    /// @notice Finalize ERC20 deposit from L1. Ensures CET at predicted address (deploy if
    ///         absent via factory, using metadata packed in `_extraData`) then `crosschainMint`.
    /// @param _localToken  L2 CET address (as predicted for `_remoteToken` at `l1ChainId`).
    /// @param _remoteToken L1 canonical token address.
    /// @param _from        L1 sender.
    /// @param _to          L2 recipient.
    /// @param _amount      Amount to mint.
    /// @param _extraData   `abi.encode(string name, string symbol, uint8 decimals, bytes user)`.
    function finalizeBridgeERC20(address _localToken, address _remoteToken, address _from, address _to, uint256 _amount, bytes calldata _extraData)
        external
        onlyOtherBridge
        nonReentrant
    {
        address predicted = cetFactory.predictAddress(_remoteToken, l1ChainId);
        if (predicted != _localToken) revert LocalTokenMismatch();

        (string memory name_, string memory symbol_, uint8 decimals_, bytes memory userExtra) = abi.decode(_extraData, (string, string, uint8, bytes));

        address cet = cetFactory.deployIfAbsent(_remoteToken, l1ChainId, decimals_, name_, symbol_);
        IComposableERC20(cet).crosschainMint(_to, _amount);

        emit DepositFinalized(_remoteToken, _localToken, _from, _to, _amount, userExtra);
        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, userExtra);
    }

    function _initiateBridgeETH(address _from, address _to, uint256 _amount, uint32 _minGasLimit, bytes memory _extraData) internal {
        if (_amount == 0) revert NoETHSent();
        if (msg.value != _amount) revert ETHValueMismatch();
        if (otherBridge == address(0)) revert NotFromOtherBridge();

        emit WithdrawalInitiated(address(0), address(0), _from, _to, _amount, _extraData);
        emit ETHBridgeInitiated(_from, _to, _amount, _extraData);

        messenger.sendMessage{value: _amount}(
            otherBridge, abi.encodeWithSignature("finalizeBridgeETH(address,address,uint256,bytes)", _from, _to, _amount, _extraData), _minGasLimit
        );
    }

    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    ) internal nonReentrant {
        if (msg.value != 0) revert CannotSendValue();
        if (otherBridge == address(0)) revert NotFromOtherBridge();

        // L2 only handles CET on the L1↔L2 leg. Ensure localToken is actually a CET and that
        // it matches the predicted address for (remoteToken on L1).
        if (!_isCET(_localToken)) revert NotCET();
        if (cetFactory.predictAddress(_remoteToken, l1ChainId) != _localToken) revert LocalTokenMismatch();

        IComposableERC20(_localToken).crosschainBurn(_from, _amount);

        emit WithdrawalInitiated(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        emit ERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        // L1-side arg order mirrors: on L1 `_localToken` is the L1 token, `_remoteToken` is L2.
        messenger.sendMessage(
            otherBridge,
            abi.encodeWithSignature(
                "finalizeBridgeERC20(address,address,address,address,uint256,bytes)", _remoteToken, _localToken, _from, _to, _amount, _extraData
            ),
            _minGasLimit
        );
    }

    function _isCET(address token) internal view returns (bool) {
        if (token.code.length == 0) return false;
        try IERC165(token).supportsInterface(type(IComposableERC20).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }
}
