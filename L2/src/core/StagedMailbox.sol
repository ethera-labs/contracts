// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { IStagedMailbox } from "./interfaces/IStagedMailbox.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract StagedMailbox is ReentrancyGuardTransient, IStagedMailbox {
    uint8 internal constant FLAG_CREATED = 0x01;
    uint8 internal constant FLAG_USED = 0x02;

    uint256[] public chainIDsInbox;
    uint256[] public chainIDsOutbox;
    mapping(uint256 => bytes32) public inboxRootPerChain;
    mapping(uint256 => bytes32) public outboxRootPerChain;

    mapping(bytes32 => uint8) public keyFlags;

    address public immutable COORDINATOR;

    mapping(bytes32 => bytes) public inbox;
    mapping(bytes32 => bytes) public outbox;

    constructor(address _coordinator) {
        if (_coordinator == address(0)) {
            revert ZeroAddress();
        }
        COORDINATOR = _coordinator;
    }

    function getKey(
        uint256 srcChainID,
        uint256 destChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label
    ) public pure returns (bytes32 key) {
        if (sender == address(0) || receiver == address(0)) {
            revert ZeroAddress();
        }

        key = keccak256(
            abi.encodePacked(srcChainID, destChainID, sender, receiver, sessionId, label)
        );
    }

    function putInbox(
        uint256 srcChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        onlyCoordinator();
        bytes32 key = getKey(srcChainID, block.chainid, sender, receiver, sessionId, label);
        if (isCreatedKey(key)) {
            revert KeyAlreadyExists(key);
        }

        setCreatedKey(key);
        inbox[key] = data;

        emit InboxMessageAdded(key);
    }

    function putOutbox(
        uint256 destChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        onlyCoordinator();
        bytes32 key = getKey(block.chainid, destChainID, sender, receiver, sessionId, label);
        if (isCreatedKey(key)) {
            revert KeyAlreadyExists(key);
        }

        setCreatedKey(key);
        outbox[key] = data;

        emit OutboxMessageAdded(key);
    }

    function read(
        uint256 srcChainID,
        address sender,
        uint256 sessionId,
        string calldata label
    ) external returns (bytes memory) {
        bytes32 key = getKey(srcChainID, block.chainid, sender, msg.sender, sessionId, label);
        if (!isCreatedKey(key)) {
            revert MessageNotFound(key);
        }
        if (isKeyUsed(key)) {
            revert MessageAlreadyUsed(key);
        }

        setUsedKey(key);

        bytes memory data = inbox[key];
        delete inbox[key];

        if (inboxRootPerChain[srcChainID] == bytes32(0)) {
            chainIDsInbox.push(srcChainID);
        }
        inboxRootPerChain[srcChainID] =
                        keccak256(abi.encode(inboxRootPerChain[srcChainID], key, data));

        emit MessageRead(key);
        return data;
    }

    function write(
        uint256 destChainID,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) external {
        bytes32 key = getKey(block.chainid, destChainID, msg.sender, receiver, sessionId, label);
        if (!isCreatedKey(key)) {
            revert MessageNotFound(key);
        }
        if (isKeyUsed(key)) {
            revert MessageAlreadyUsed(key);
        }

        bytes memory stored = outbox[key];

        if (keccak256(stored) != keccak256(data)) {
            revert MessageDataMismatch(key);
        }

        setUsedKey(key);
        delete outbox[key];

        if (outboxRootPerChain[destChainID] == bytes32(0)) {
            chainIDsOutbox.push(destChainID);
        }
        outboxRootPerChain[destChainID] =
                        keccak256(abi.encode(outboxRootPerChain[destChainID], key, stored));

        emit MessageWritten(key);
    }

    function safeExecute(
        StagedInboxMsg[] calldata stagedInboxMsgs,
        StagedOutboxMsg[] calldata stagedOutboxMsgs,
        address target,
        bytes calldata mainTxData
    ) external nonReentrant {
        onlyCoordinator();
        uint256 inLen = stagedInboxMsgs.length;
        uint256 outLen = stagedOutboxMsgs.length;

        for (uint256 i = 0; i < inLen; i++) {
            StagedInboxMsg calldata m = stagedInboxMsgs[i];
            putInbox(m.srcChainID, m.sender, m.receiver, m.sessionId, m.label, m.data);
        }

        for (uint256 i = 0; i < outLen; i++) {
            StagedOutboxMsg calldata m = stagedOutboxMsgs[i];
            putOutbox(m.destChainID, m.sender, m.receiver, m.sessionId, m.label, m.data);
        }

        (bool success, bytes memory data) = target.call(mainTxData);
        if (!success) {
            revert MainCallFailed(data);
        }
    }

    function onlyCoordinator() internal view {
        if (msg.sender != COORDINATOR) {
            revert OnlyCoordinatorAllowed();
        }
    }

    function setCreatedKey(bytes32 key) internal {
        keyFlags[key] |= FLAG_CREATED;
    }

    function isCreatedKey(bytes32 key) public view returns (bool) {
        return keyFlags[key] & FLAG_CREATED != 0;
    }

    function setUsedKey(bytes32 key) internal {
        keyFlags[key] |= FLAG_USED;
    }

    function isKeyUsed(bytes32 key) public view returns (bool) {
        return keyFlags[key] & FLAG_USED != 0;
    }
}