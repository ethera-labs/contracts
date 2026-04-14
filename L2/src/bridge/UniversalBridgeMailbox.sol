// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { IUniversalBridgeMailbox } from "@ssv/src/bridge/interfaces/IUniversalBridgeMailbox.sol";

contract UniversalBridgeMailbox is IUniversalBridgeMailbox {

    address public immutable COORDINATOR;
    mapping(address => bool) public authorizedBridges;
    address public immutable owner;

    uint256[] public chainIDsInbox;
    uint256[] public chainIDsOutbox;

    mapping(uint256 chainId => bytes32 inboxRoot) public inboxRootPerChain;
    mapping(uint256 chainId => bytes32 outboxRoot) public outboxRootPerChain;

    mapping(bytes32 key => bytes message) public inbox;
    mapping(bytes32 key => bytes message) public outbox;

    mapping(bytes32 key => bool used) public createdKeys;
    mapping(bytes32 key => bool consumed) public consumedKeys;

    MessageHeader[] public messageHeaderListInbox;
    MessageHeader[] public messageHeaderListOutbox;

    error OnlyBridge();
    error OnlyDeployer();
    error ZeroAddress();
    error MessageAlreadyConsumed();
    error KeyAlreadyExists();

    modifier onlyCoordinator() {
        if (msg.sender != COORDINATOR) revert InvalidCoordinator();
        _;
    }

    modifier onlyBridge() {
        if (!authorizedBridges[msg.sender]) revert OnlyBridge();
        _;
    }

    constructor(address _coordinator) {
        COORDINATOR = _coordinator;
        owner = msg.sender;
    }

    function authorizeBridge(address _bridge) external {
        if (msg.sender != owner) revert OnlyDeployer();
        if (_bridge == address(0)) revert ZeroAddress();
        authorizedBridges[_bridge] = true;
    }

    function revokeBridge(address _bridge) external {
        if (msg.sender != owner) revert OnlyDeployer();
        authorizedBridges[_bridge] = false;
    }

    function getKey(
        uint256 chainMessageSender,
        uint256 chainMessageRecipient,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label
    ) public pure returns (bytes32 key) {
        key = keccak256(
            abi.encodePacked(
                chainMessageSender,
                chainMessageRecipient,
                sender,
                receiver,
                sessionId,
                label
            )
        );
    }

    function putInbox(
        uint256 chainMessageSender,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) external onlyCoordinator {
        bytes32 key = getKey(
            chainMessageSender,
            block.chainid,
            sender,
            receiver,
            sessionId,
            label
        );

        if (createdKeys[key]) {
            revert KeyAlreadyExists();
        }

        createdKeys[key] = true;
        inbox[key] = data;

        messageHeaderListInbox.push(
            MessageHeader(chainMessageSender, block.chainid, sender, receiver, sessionId, label)
        );

        if (inboxRootPerChain[chainMessageSender] == bytes32(0)) {
            chainIDsInbox.push(chainMessageSender);
        }

        inboxRootPerChain[chainMessageSender] = keccak256(
            abi.encode(inboxRootPerChain[chainMessageSender], key, data)
        );

        emit NewInboxKey(messageHeaderListInbox.length - 1, key);
    }

    function readMessage(
        MessageHeader calldata header
    ) external onlyBridge returns (bytes memory message) {
        bytes32 key = getKey(
            header.chainSrc,
            header.chainDest,
            header.sender,
            header.receiver,
            header.sessionId,
            header.label
        );

        if (inbox[key].length == 0 && !createdKeys[key]) {
            revert MessageNotFound();
        }

        if (consumedKeys[key]) {
            revert MessageAlreadyConsumed();
        }

        consumedKeys[key] = true;

        bytes memory message = inbox[key];
        delete inbox[key];

        return message;
    }

    function writeMessage(
        Message calldata _message
    ) external onlyBridge {
        MessageHeader calldata h = _message.header;
        bytes32 key = getKey(
            block.chainid,
            h.chainDest,
            msg.sender,
            h.receiver,
            h.sessionId,
            h.label
        );

        outbox[key] = _message.payload;
        createdKeys[key] = true;

        messageHeaderListOutbox.push(
            MessageHeader(
                block.chainid,
                h.chainDest,
                msg.sender,
                h.receiver,
                h.sessionId,
                h.label
            )
        );

        if (outboxRootPerChain[h.chainDest] == bytes32(0)) {
            chainIDsOutbox.push(h.chainDest);
        }
        outboxRootPerChain[h.chainDest] = keccak256(
            abi.encode(outboxRootPerChain[h.chainDest], key, _message.payload)
        );

        emit NewOutboxKey(messageHeaderListOutbox.length - 1, key);
    }

    function computeKey(uint256 id) external view returns (bytes32) {
        if (id >= messageHeaderListInbox.length) {
            revert InvalidId();
        }

        MessageHeader storage m = messageHeaderListInbox[id];

        return keccak256(
            abi.encodePacked(
                m.chainSrc,
                m.chainDest,
                m.sender,
                m.receiver,
                m.sessionId,
                m.label
            )
        );
    }
}