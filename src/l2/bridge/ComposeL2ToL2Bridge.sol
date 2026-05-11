// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.18;

import {IComposeL2ToL2Bridge} from "./interfaces/IComposeL2ToL2Bridge.sol";
import { ICETFactory } from "src/l2/bridge/interfaces/ICETFactory.sol";
import {IComposableERC20} from "src/l2/bridge/interfaces/IComposableERC20.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IETHLiquidity} from "src/l2/bridge/interfaces/external/IETHLiquidity.sol";
import {IUniversalBridgeMailbox} from "src/l2/bridge/interfaces/IUniversalBridgeMailbox.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ComposeL2ToL2Bridge is IComposeL2ToL2Bridge, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IUniversalBridgeMailbox public immutable mailbox;
    ICETFactory public immutable cetFactory;
    IETHLiquidity public immutable ethLiquidity;

    constructor(address _mailbox, address _cetFactory, address _ethLiquidity) {
        mailbox = IUniversalBridgeMailbox(_mailbox);
        cetFactory = ICETFactory(_cetFactory);
        ethLiquidity = IETHLiquidity(_ethLiquidity);
    }

    receive() external payable {}

    function computeCETAddress(
        address remoteAsset,
        uint256 remoteChainID
    ) internal view returns (address) {
        return cetFactory.predictAddress(remoteAsset, remoteChainID);
    }

    function _isComposableERC20(address token) internal view returns (bool) {
        if (token.code.length == 0) return false;
        try IERC165(token).supportsInterface(type(IComposableERC20).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    function isCoreComposeable(address token) internal view returns (bool) {
        try IComposableERC20(token).cetType() returns (IComposableERC20.CetType t) {
            return t == IComposableERC20.CetType.CORE;
        } catch {
            return false;
        }
    }

    function ensureCETAndMint(
        address remoteAsset,
        uint256 remoteChainID,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address to,
        uint256 amount
    ) internal returns (address cet) {
        if (remoteAsset.code.length > 0 && isCoreComposeable(remoteAsset)) {
            IComposableERC20(remoteAsset).crosschainMint(to, amount);
            return remoteAsset;
        }

        address predicted = computeCETAddress(remoteAsset, remoteChainID);

        cet = cetFactory.deployIfAbsent(
            remoteAsset,
            remoteChainID,
            decimals,
            name,
            symbol
        );

        if (cet != predicted) revert InvalidCetAddress();

        IComposableERC20(cet).crosschainMint(to, amount);
        return cet;
    }

    function bridgeERC20To(
        uint256 chainDest,
        address tokenSrc,
        uint256 amount,
        address receiver,
        uint256 sessionId
    ) external nonReentrant {
        if (_isComposableERC20(tokenSrc)) revert UseBridgeCETTo();
        address sender = msg.sender;

        IERC20(tokenSrc).safeTransferFrom(sender, address(this), amount);
        emit TokensLocked(tokenSrc, sender, amount);

        string memory name = IERC20Metadata(tokenSrc).name();
        string memory symbol = IERC20Metadata(tokenSrc).symbol();
        uint8 decimals = IERC20Metadata(tokenSrc).decimals();
        bytes memory payload = abi.encode(block.chainid, tokenSrc, amount, name, symbol, decimals);

        IUniversalBridgeMailbox.MessageHeader memory sendHeader = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: block.chainid,
            chainDest: chainDest,
            sender: address(this),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_TOKENS"
        });
        mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: sendHeader, payload: payload}));
        checkAck(sessionId, chainDest, receiver, address(this), tokenSrc, amount);
        emit MailboxWrite(chainDest, receiver, sessionId, "SEND_TOKENS");

        bytes32 messageId = keccak256(
            abi.encodePacked(chainDest, receiver, sessionId, "SEND_TOKENS")
        );
        emit TokensSendQueued(chainDest, sender, receiver, tokenSrc, amount, sessionId, messageId);
    }

    function bridgeCETTo(
        uint256 chainDest,
        address cetTokenSrc,
        uint256 amount,
        address receiver,
        uint256 sessionId
    ) external nonReentrant {
        address remoteAsset = IComposableERC20(cetTokenSrc).remoteAsset();

        IComposableERC20(cetTokenSrc).crosschainBurn(msg.sender, amount);
        emit CETBurned(cetTokenSrc, msg.sender, amount);

        {
            uint256 remoteChainID = IComposableERC20(cetTokenSrc).remoteChainID();
            bytes memory payload = abi.encode(
                remoteChainID, remoteAsset, amount,
                IERC20Metadata(cetTokenSrc).name(),
                IERC20Metadata(cetTokenSrc).symbol(),
                IERC20Metadata(cetTokenSrc).decimals()
            );

            IUniversalBridgeMailbox.MessageHeader memory sendHeader = IUniversalBridgeMailbox.MessageHeader({
                chainSrc: block.chainid,
                chainDest: chainDest,
                sender: address(this),
                receiver: receiver,
                sessionId: sessionId,
                label: "SEND_TOKENS"
            });
            mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: sendHeader, payload: payload}));
        }

        checkAck(sessionId, chainDest, receiver, address(this), remoteAsset, amount);
        emit MailboxWrite(chainDest, receiver, sessionId, "SEND_TOKENS");

        bytes32 messageId = keccak256(
            abi.encodePacked(chainDest, receiver, sessionId, "SEND_TOKENS")
        );
        emit TokensSendQueued(chainDest, msg.sender, receiver, remoteAsset, amount, sessionId, messageId);
    }

    function bridgeEthTo(
        uint256 sessionId,
        uint256 chainDest,
        address receiver
    ) external payable nonReentrant {
        if (msg.value == 0) revert NoETHSent();

        ethLiquidity.burn{value: msg.value}();
        emit ETHLocked(msg.sender, msg.value);

        bytes memory payload = abi.encode(block.chainid, msg.value);

        IUniversalBridgeMailbox.MessageHeader memory sendHeader = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: block.chainid,
            chainDest: chainDest,
            sender: address(this),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_ETH"
        });
        mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: sendHeader, payload: payload}));
        checkAck(sessionId, chainDest, receiver, address(this), address(0), msg.value);
        emit MailboxWrite(chainDest, receiver, sessionId, "SEND_ETH");

        bytes32 messageId = keccak256(
            abi.encodePacked(chainDest, receiver, sessionId, "SEND_ETH")
        );
        emit ETHBridged(chainDest, msg.sender, receiver, msg.value, sessionId, messageId);
    }

    function receiveTokens(
        IUniversalBridgeMailbox.MessageHeader calldata msgHeader
    ) external nonReentrant returns (address token, uint256 amount) {
        if (msg.sender != msgHeader.receiver) revert NotReceiver();
        if (msgHeader.chainDest != block.chainid) revert WrongDestinationChain();
        if (keccak256(bytes(msgHeader.label)) != keccak256("SEND_TOKENS")) revert InvalidMessage();

        bytes memory m = mailbox.readMessage(msgHeader);
        if (m.length == 0) revert NoSendMessage();

        uint256 remoteChainID;
        address remoteAsset;
        string memory name;
        string memory symbol;
        uint8 decimals;
        (remoteChainID, remoteAsset, amount, name, symbol, decimals) =
        abi.decode(m, (uint256, address, uint256, string, string, uint8));

        if (remoteChainID == block.chainid) {
            if (IERC20(remoteAsset).balanceOf(address(this)) < amount) revert InsufficientEscrowBalance();
            IERC20(remoteAsset).safeTransfer(msgHeader.receiver, amount);
            token = remoteAsset;
        } else {
            token = ensureCETAndMint(
                remoteAsset,
                remoteChainID,
                name,
                symbol,
                decimals,
                msgHeader.receiver,
                amount
            );
        }

        IUniversalBridgeMailbox.MessageHeader memory ackHeader = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: msgHeader.chainDest,
            chainDest: msgHeader.chainSrc,
            sender: msgHeader.receiver,
            receiver: msgHeader.sender,
            sessionId: msgHeader.sessionId,
            label: "ACK"
        });
        mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: ackHeader, payload: abi.encode(remoteAsset, amount)}));
        emit MailboxAckWrite(msgHeader.chainSrc, msgHeader.sender, msgHeader.sessionId, "ACK");
        emit TokensReceived(token, amount);
    }

    function receiveETH(
        IUniversalBridgeMailbox.MessageHeader calldata msgHeader
    ) external nonReentrant returns (uint256 amount) {
        if (msg.sender != msgHeader.receiver) revert NotReceiver();
        if (msgHeader.chainDest != block.chainid) revert WrongDestinationChain();
        if (keccak256(bytes(msgHeader.label)) != keccak256("SEND_ETH")) revert InvalidMessage();

        bytes memory m = mailbox.readMessage(msgHeader);
        if (m.length == 0) revert NoSendMessage();

        uint256 remoteChainID;
        (remoteChainID, amount) = abi.decode(m, (uint256, uint256));

        ethLiquidity.mint(amount);
        (bool ok,) = msgHeader.receiver.call{value: amount}("");
        if (!ok) revert TransferFailed();

        IUniversalBridgeMailbox.MessageHeader memory ackHeader = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: msgHeader.chainDest,
            chainDest: msgHeader.chainSrc,
            sender: msgHeader.receiver,
            receiver: msgHeader.sender,
            sessionId: msgHeader.sessionId,
            label: "ACK"
        });
        mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: ackHeader, payload: abi.encode(address(0), amount)}));
        emit MailboxAckWrite(msgHeader.chainSrc, msgHeader.sender, msgHeader.sessionId, "ACK");
        emit ETHReceived(msgHeader.receiver, amount);
    }

    function redeemWrappedCET(
        address wrappedCET,
        address coreCET,
        uint256 amount
    ) external nonReentrant {
        if (wrappedCET == address(0) || coreCET == address(0)) revert ZeroAddress();
        if (!isCoreComposeable(coreCET)) revert NotCoreComposeable();
        if (IComposableERC20(wrappedCET).remoteAsset() != coreCET) revert AssetMismatch();

        IComposableERC20(wrappedCET).crosschainBurn(msg.sender, amount);
        IComposableERC20(coreCET).crosschainMint(msg.sender, amount);
        emit WrappedCETRedeemed(wrappedCET, coreCET, msg.sender, amount);
    }

    function checkAck(
        uint256 sessionId,
        uint256 ackChainSrc,
        address ackSender,
        address ackReceiver,
        address tokenSrc,
        uint256 amount
    ) internal {
        IUniversalBridgeMailbox.MessageHeader memory ackHeader = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: ackChainSrc,
            chainDest: block.chainid,
            sender: ackSender,
            receiver: ackReceiver,
            sessionId: sessionId,
            label: "ACK"
        });
        bytes memory ackPayload = mailbox.readMessage(ackHeader);
        if (ackPayload.length == 0) revert NoAckMessage();

        (address ackTokenSrc, uint256 ackAmount) = abi.decode(ackPayload, (address, uint256));
        if (ackTokenSrc != tokenSrc) revert AckTokenMismatch();
        if (ackAmount != amount) revert AckAmountMismatch();
    }
}