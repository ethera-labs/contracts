// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.18;

interface IUniversalBridgeMailbox {
    struct MessageHeader {
        uint256 chainSrc;
        uint256 chainDest;
        address sender;
        address receiver;
        uint256 sessionId;
        string label;
    }

    struct Message {
        MessageHeader header;
        bytes payload;
    }

    error InvalidCoordinator();
    error MessageNotFound();
    error InvalidId();

    event NewInboxKey(uint256 indexed index, bytes32 key);
    event NewOutboxKey(uint256 indexed index, bytes32 key);

    function readMessage(MessageHeader calldata header) external returns (bytes memory message);

    function writeMessage(Message calldata message) external;

    function putInbox(uint256 chainSrc, address sender, address receiver, uint256 sessionId, string calldata label, bytes calldata data) external;
}
