// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

/**
 * @title IStagedMailbox
 * @notice Interface for a cross-chain messaging system that manages staged inbox/outbox messages
 *         and allows atomic message execution across rollups.
 */
interface IStagedMailbox {
    error MessageNotFound(bytes32 key);
    error MessageAlreadyUsed(bytes32 key);
    error MessageDataMismatch(bytes32 key);
    error KeyAlreadyExists(bytes32 key);
    error OnlyCoordinatorAllowed();
    error TooManyMessages();
    error MainCallFailed(bytes data);
    error ZeroAddress();

    event InboxMessageAdded(bytes32 indexed key);
    event OutboxMessageAdded(bytes32 indexed key);
    event MessageRead(bytes32 indexed key);
    event MessageWritten(bytes32 indexed key);

    struct MessageHeader {
        uint256 chainSrc;
        uint256 chainDest;
        address sender;
        address receiver;
        uint256 sessionId;
        string label;
    }

    struct StagedInboxMsg {
        uint256 srcChainID;
        address sender;
        address receiver;
        uint256 sessionId;
        string label;
        bytes data;
    }

    struct StagedOutboxMsg {
        uint256 destChainID;
        address sender;
        address receiver;
        uint256 sessionId;
        string label;
        bytes data;
    }

    function COORDINATOR() external view returns (address);

    function inboxRootPerChain(uint256 chainId) external view returns (bytes32);
    function outboxRootPerChain(uint256 chainId) external view returns (bytes32);

    function inbox(bytes32 key) external view returns (bytes memory);
    function outbox(bytes32 key) external view returns (bytes memory);

    function getKey(
        uint256 srcChainID,
        uint256 destChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label
    ) external pure returns (bytes32);

    function putInbox(
        uint256 srcChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) external;

    function putOutbox(
        uint256 destChainID,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) external;

    function read(
        uint256 srcChainID,
        address sender,
        uint256 sessionId,
        string calldata label
    ) external returns (bytes memory);

    function write(
        uint256 destChainID,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) external;

    function safeExecute(
        StagedInboxMsg[] calldata stagedInboxMsgs,
        StagedOutboxMsg[] calldata stagedOutboxMsgs,
        address target,
        bytes calldata mainTxData
    ) external;
}