// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IStagedMailbox} from "@ssv/src/core/interfaces/IStagedMailbox.sol";
import {StagedMailbox} from "@ssv/src/core/StagedMailbox.sol";
import {Setup} from "@ssv/test/Setup.t.sol";

contract StagedMailboxTest is Setup {
    uint256 internal thisChain = block.chainid;
    uint256 internal otherChain = 2;

    address internal messageSender = address(0xabc);
    address internal messageReceiver = address(0x123);

    /// @dev Tests constructor sets coordinator correctly and reverts for zero address
    function testConstructor() public {
        assertEq(
            stagedMailbox.COORDINATOR(),
            COORDINATOR,
            "Coordinator should be set"
        );

        vm.expectRevert(IStagedMailbox.ZeroAddress.selector);
        new StagedMailbox(address(0));
    }

    /// @dev Tests that non-coordinator cannot write to inbox
    function testShouldRevertNonCoordinatorToWriteToInbox() public {
        vm.prank(messageSender);
        vm.expectRevert(IStagedMailbox.OnlyCoordinatorAllowed.selector);
        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "hello");
    }

    /// @dev Tests that non-coordinator cannot write to outbox
    function testShouldRevertNonCoordinatorToWriteToOutbox() public {
        vm.prank(messageSender);
        vm.expectRevert(IStagedMailbox.OnlyCoordinatorAllowed.selector);
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "hello");
    }

    /// @dev Tests writing a single message to inbox by coordinator
    function testWriteInboxSingle() public returns (bytes32 key) {
        vm.startPrank(COORDINATOR);

        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.InboxMessageAdded(
            stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP")
        );

        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "salut");
        vm.stopPrank();

        key = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        assertEq(stagedMailbox.inbox(key), "salut", "The message should match");
        assertTrue(stagedMailbox.isCreatedKey(key), "Key should be created");
        assertFalse(stagedMailbox.isKeyUsed(key), "Key should not be used yet");
    }

    /// @dev Tests writing a single message to outbox by coordinator
    function testWriteOutboxSingle() public returns (bytes32 key) {
        vm.startPrank(COORDINATOR);

        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.OutboxMessageAdded(
            stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP")
        );

        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "hello");
        vm.stopPrank();

        key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");
        assertEq(stagedMailbox.outbox(key), "hello", "The message should match");
        assertTrue(stagedMailbox.isCreatedKey(key), "Key should be created");
        assertFalse(stagedMailbox.isKeyUsed(key), "Key should not be used yet");
    }

    /// @dev Tests writing multiple messages to inbox
    function testWriteInboxMultiple() public {
        bytes32 key1 = testWriteInboxSingle();

        vm.startPrank(COORDINATOR);

        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.InboxMessageAdded(
            stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 2, "SWAP")
        );

        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 2, "SWAP", "salut2");
        vm.stopPrank();

        bytes32 key2 = stagedMailbox.getKey(
            otherChain,
            thisChain,
            messageSender,
            messageReceiver,
            2,
            "SWAP"
        );
        assertEq(stagedMailbox.inbox(key1), "salut", "First message should remain");
        assertEq(stagedMailbox.inbox(key2), "salut2", "Second message should match");
    }

    /// @dev Tests writing multiple messages to outbox
    function testWriteOutboxMultiple() public {
        bytes32 key1 = testWriteOutboxSingle();

        vm.startPrank(COORDINATOR);

        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.OutboxMessageAdded(
            stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 2, "SWAP")
        );

        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 2, "SWAP", "hello2");
        vm.stopPrank();

        bytes32 key2 = stagedMailbox.getKey(
            thisChain,
            otherChain,
            messageSender,
            messageReceiver,
            2,
            "SWAP"
        );
        assertEq(stagedMailbox.outbox(key1), "hello", "First message should remain");
        assertEq(stagedMailbox.outbox(key2), "hello2", "Second message should match");
    }

    /// @dev Tests reading a message from inbox
    function testRead() public {
        testWriteInboxSingle();
        bytes32 key = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        vm.prank(messageReceiver);
        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.MessageRead(key);

        bytes memory data = stagedMailbox.read(
            otherChain,
            messageSender,
            1,
            "SWAP"
        );
        assertEq(data, "salut", "Should match the read message");
        assertTrue(stagedMailbox.isKeyUsed(key), "Key should be marked as used");
        assertEq(stagedMailbox.inbox(key), "", "Inbox message should be deleted");
        bytes32 expectedRoot = keccak256(abi.encode(bytes32(0), key, "salut"));
        assertEq(stagedMailbox.inboxRootPerChain(otherChain), expectedRoot, "Inbox root should match");
    }

    /// @dev Tests reading an empty but created message returns empty data
    function testReadEmptyCreated() public {
        vm.prank(COORDINATOR);
        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "");
        vm.prank(messageReceiver);
        bytes memory data = stagedMailbox.read(
            otherChain,
            messageSender,
            1,
            "SWAP"
        );
        assertEq(data, "", "Should return empty message");
    }

    /// @dev Tests reading non-existent message reverts
    function testReadNotFound() public {
        bytes32 key = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        vm.prank(messageReceiver);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageNotFound.selector, key));
        stagedMailbox.read(otherChain, messageSender, 1, "SWAP");
    }

    /// @dev Tests reading an already used message reverts
    function testReadAlreadyUsed() public {
        bytes32 key = testWriteInboxSingle();
        vm.prank(messageReceiver);
        stagedMailbox.read(otherChain, messageSender, 1, "SWAP");
        vm.prank(messageReceiver);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageAlreadyUsed.selector, key));
        stagedMailbox.read(otherChain, messageSender, 1, "SWAP");
    }

    /// @dev Tests writing a message to outbox
    function testWrite() public {
        vm.prank(COORDINATOR);
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "hello");
        bytes32 key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");

        vm.prank(messageSender);
        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.MessageWritten(key);

        stagedMailbox.write(otherChain, messageReceiver, 1, "SWAP", "hello");
        assertTrue(stagedMailbox.isKeyUsed(key), "Key should be marked as used");
        assertEq(stagedMailbox.outbox(key), "", "Outbox message should be deleted");
        bytes32 expectedRoot = keccak256(abi.encode(bytes32(0), key, "hello"));
        assertEq(stagedMailbox.outboxRootPerChain(otherChain), expectedRoot, "Outbox root should match");
    }

    /// @dev Tests writing with non-existent key reverts
    function testWriteNonExistentKey() public {
        bytes32 key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");
        vm.prank(messageSender);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageNotFound.selector, key));
        stagedMailbox.write(otherChain, messageReceiver, 1, "SWAP", "hello");
    }

    /// @dev Tests writing with already used key reverts
    function testWriteAlreadyUsed() public {
        bytes32 key = testWriteOutboxSingle();
        vm.prank(messageSender);
        stagedMailbox.write(otherChain, messageReceiver, 1, "SWAP", "hello");
        vm.prank(messageSender);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageAlreadyUsed.selector, key));
        stagedMailbox.write(otherChain, messageReceiver, 1, "SWAP", "hello");
    }

    /// @dev Tests writing with data mismatch reverts
    function testWriteDataMismatch() public {
        vm.prank(COORDINATOR);
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "hello");
        bytes32 key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");
        vm.prank(messageSender);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageDataMismatch.selector, key));
        stagedMailbox.write(otherChain, messageReceiver, 1, "SWAP", "different");
    }

    /// @dev Tests safeExecute with inbox and outbox messages
    function testSafeExecute() public {
        address target = address(new MockTarget());

        IStagedMailbox.StagedInboxMsg[] memory inboxMsgs = new IStagedMailbox.StagedInboxMsg[](1);
        inboxMsgs[0] = IStagedMailbox.StagedInboxMsg({
            srcChainID: otherChain,
            sender: messageSender,
            receiver: messageReceiver,
            sessionId: 1,
            label: "SWAP",
            data: "salut"
        });

        IStagedMailbox.StagedOutboxMsg[] memory outboxMsgs = new IStagedMailbox.StagedOutboxMsg[](1);
        outboxMsgs[0] = IStagedMailbox.StagedOutboxMsg({
            destChainID: otherChain,
            sender: messageSender,
            receiver: messageReceiver,
            sessionId: 1,
            label: "SWAP",
            data: "hello"
        });

        bytes memory mainTxData = abi.encodeWithSignature("doSomething()");

        vm.startPrank(COORDINATOR);
        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.InboxMessageAdded(
            stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP")
        );
        vm.expectEmit(true, false, false, true);
        emit IStagedMailbox.OutboxMessageAdded(
            stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP")
        );

        stagedMailbox.safeExecute(inboxMsgs, outboxMsgs, target, mainTxData);

        bytes32 inboxKey = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        bytes32 outboxKey = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");

        assertEq(stagedMailbox.inbox(inboxKey), "salut", "Inbox message should be set");
        assertEq(stagedMailbox.outbox(outboxKey), "hello", "Outbox message should be set");
        assertTrue(stagedMailbox.isCreatedKey(inboxKey), "Inbox key should be created");
        assertTrue(stagedMailbox.isCreatedKey(outboxKey), "Outbox key should be created");
        vm.stopPrank();
    }

    /// @dev Tests safeExecute reverts on failed target call
    function testSafeExecuteFailedCall() public {
        address target = address(new MockTarget());
        IStagedMailbox.StagedInboxMsg[] memory inboxMsgs = new IStagedMailbox.StagedInboxMsg[](0);
        IStagedMailbox.StagedOutboxMsg[] memory outboxMsgs = new IStagedMailbox.StagedOutboxMsg[](0);
        bytes memory mainTxData = abi.encodeWithSignature("fail()");

        vm.prank(COORDINATOR);
        vm.expectRevert();
        stagedMailbox.safeExecute(inboxMsgs, outboxMsgs, target, mainTxData);
    }

    /// @dev Tests getKey is consistent
    function testGetKeyPure() public view {
        bytes32 key1 = stagedMailbox.getKey(
            1,
            2,
            address(0xA),
            address(0xB),
            1,
            "LABEL"
        );
        bytes32 key2 = stagedMailbox.getKey(
            1,
            2,
            address(0xA),
            address(0xB),
            1,
            "LABEL"
        );
        assertEq(key1, key2, "Keys should be the same");
        bytes32 keyDiff = stagedMailbox.getKey(
            1,
            2,
            address(0xA),
            address(0xB),
            1,
            "DIFF"
        );
        assertNotEq(
            key1,
            keyDiff,
            "Different labels should give different keys"
        );
    }

    /// @dev Tests that duplicate keys in putInbox are rejected
    function testPutInboxDuplicateKeyReverts() public {
        vm.startPrank(COORDINATOR);
        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "data1");

        bytes32 key = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.KeyAlreadyExists.selector, key));
        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "data2");
        vm.stopPrank();
    }

    /// @dev Tests that duplicate keys in putOutbox are rejected
    function testPutOutboxDuplicateKeyReverts() public {
        vm.startPrank(COORDINATOR);
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "data1");

        bytes32 key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "SWAP");
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.KeyAlreadyExists.selector, key));
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "SWAP", "data2");
        vm.stopPrank();
    }

    /// @dev Tests that read properly deletes inbox storage
    function testReadDeletesInboxStorage() public {
        vm.prank(COORDINATOR);
        stagedMailbox.putInbox(otherChain, messageSender, messageReceiver, 1, "MSG", "data");

        bytes32 key = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "MSG");
        assertEq(stagedMailbox.inbox(key), "data", "Data should exist before read");

        vm.prank(messageReceiver);
        stagedMailbox.read(otherChain, messageSender, 1, "MSG");

        assertEq(stagedMailbox.inbox(key), "", "Data should be deleted after read");
        assertTrue(stagedMailbox.isCreatedKey(key), "Created key should still be true");
        assertTrue(stagedMailbox.isKeyUsed(key), "Used key should be true");
    }

    /// @dev Tests that write properly deletes outbox storage
    function testWriteDeletesOutboxStorage() public {
        vm.prank(COORDINATOR);
        stagedMailbox.putOutbox(otherChain, messageSender, messageReceiver, 1, "MSG", "data");

        bytes32 key = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 1, "MSG");
        assertEq(stagedMailbox.outbox(key), "data", "Data should exist before write");

        vm.prank(messageSender);
        stagedMailbox.write(otherChain, messageReceiver, 1, "MSG", "data");

        assertEq(stagedMailbox.outbox(key), "", "Data should be deleted after write");
        assertTrue(stagedMailbox.isCreatedKey(key), "Created key should still be true");
        assertTrue(stagedMailbox.isKeyUsed(key), "Used key should be true");
    }

    /// @dev Tests that safeExecute reverts don't leave partial state
    function testSafeExecuteFailureLeavesNoPartialState() public {
        address target = address(new MockTarget());

        IStagedMailbox.StagedInboxMsg[] memory inboxMsgs = new IStagedMailbox.StagedInboxMsg[](1);
        inboxMsgs[0] = IStagedMailbox.StagedInboxMsg({
            srcChainID: otherChain,
            sender: messageSender,
            receiver: messageReceiver,
            sessionId: 1,
            label: "SWAP",
            data: "salut"
        });

        IStagedMailbox.StagedOutboxMsg[] memory outboxMsgs = new IStagedMailbox.StagedOutboxMsg[](1);
        outboxMsgs[0] = IStagedMailbox.StagedOutboxMsg({
            destChainID: otherChain,
            sender: messageSender,
            receiver: messageReceiver,
            sessionId: 2,
            label: "SWAP",
            data: "hello"
        });

        bytes memory failTxData = abi.encodeWithSignature("fail()");

        vm.prank(COORDINATOR);
        vm.expectRevert();
        stagedMailbox.safeExecute(inboxMsgs, outboxMsgs, target, failTxData);

        // Verify no messages were stored due to revert
        bytes32 inboxKey = stagedMailbox.getKey(otherChain, thisChain, messageSender, messageReceiver, 1, "SWAP");
        bytes32 outboxKey = stagedMailbox.getKey(thisChain, otherChain, messageSender, messageReceiver, 2, "SWAP");

        assertFalse(stagedMailbox.isCreatedKey(inboxKey), "Inbox key should not be created on failure");
        assertFalse(stagedMailbox.isKeyUsed(outboxKey), "Outbox key should not be created on failure");
    }

    /// @dev Tests safeExecute with empty arrays
    function testSafeExecuteEmptyArrays() public {
        address target = address(new MockTarget());
        IStagedMailbox.StagedInboxMsg[] memory inboxMsgs = new IStagedMailbox.StagedInboxMsg[](0);
        IStagedMailbox.StagedOutboxMsg[] memory outboxMsgs = new IStagedMailbox.StagedOutboxMsg[](0);
        bytes memory mainTxData = abi.encodeWithSignature("doSomething()");

        vm.prank(COORDINATOR);
        stagedMailbox.safeExecute(inboxMsgs, outboxMsgs, target, mainTxData);
        // Should succeed with no state changes
    }

    /// @dev Tests safeExecute with large batches
    function testSafeExecuteLargeBatch() public {
        address target = address(new MockTarget());

        uint256 batchSize = 10;
        IStagedMailbox.StagedInboxMsg[] memory inboxMsgs = new IStagedMailbox.StagedInboxMsg[](batchSize);
        IStagedMailbox.StagedOutboxMsg[] memory outboxMsgs = new IStagedMailbox.StagedOutboxMsg[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            inboxMsgs[i] = IStagedMailbox.StagedInboxMsg({
                srcChainID: otherChain,
                sender: messageSender,
                receiver: messageReceiver,
                sessionId: i + 1,
                label: string(abi.encodePacked("MSG", i)),
                data: bytes(abi.encodePacked("data", i))
            });

            outboxMsgs[i] = IStagedMailbox.StagedOutboxMsg({
                destChainID: otherChain,
                sender: messageSender,
                receiver: messageReceiver,
                sessionId: i + 100,
                label: string(abi.encodePacked("MSG", i)),
                data: bytes(abi.encodePacked("data", i))
            });
        }

        bytes memory mainTxData = abi.encodeWithSignature("doSomething()");

        vm.prank(COORDINATOR);
        stagedMailbox.safeExecute(inboxMsgs, outboxMsgs, target, mainTxData);

        // Verify all messages were stored
        for (uint256 i = 0; i < batchSize; i++) {
            bytes32 inboxKey = stagedMailbox.getKey(
                otherChain, thisChain, messageSender, messageReceiver, i + 1, string(abi.encodePacked("MSG", i))
            );
            assertTrue(stagedMailbox.isCreatedKey(inboxKey), "Inbox message should be created");
        }
    }

    /// @dev Fuzz test for getKey uniqueness
    function testFuzz_GetKeyUniqueness(
        uint256 srcChain,
        uint256 destChain,
        address sender,
        address receiver,
        uint256 sessionId,
        string calldata label
    ) public view {
        vm.assume(sender != address(0) && receiver != address(0));
        bytes32 key = stagedMailbox.getKey(srcChain, destChain, sender, receiver, sessionId, label);
        assertNotEq(key, bytes32(0), "Key should never be zero");
    }

    /// @dev Fuzz test for putInbox/read consistency
    function testFuzz_InboxReadConsistency(
        uint256 srcChain,
        address sender,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId > 0);

        vm.prank(COORDINATOR);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId, label, data);

        vm.prank(messageReceiver);
        bytes memory retrieved = stagedMailbox.read(srcChain, sender, sessionId, label);

        assertEq(retrieved, data, "Data should match");
    }

    /// @dev Fuzz test for write data validation
    function testFuzz_WriteDataValidation(
        uint256 destChain,
        uint256 sessionId,
        string calldata label,
        bytes calldata correctData,
        bytes calldata wrongData
    ) public {
        vm.assume(sessionId > 0);
        vm.assume(keccak256(correctData) != keccak256(wrongData));

        vm.prank(COORDINATOR);
        stagedMailbox.putOutbox(destChain, messageSender, messageReceiver, sessionId, label, correctData);

        bytes32 key = stagedMailbox.getKey(thisChain, destChain, messageSender, messageReceiver, sessionId, label);

        vm.prank(messageSender);
        vm.expectRevert(abi.encodeWithSelector(IStagedMailbox.MessageDataMismatch.selector, key));
        stagedMailbox.write(destChain, messageReceiver, sessionId, label, wrongData);
    }

    /// @dev Fuzz test for inbox root calculation accuracy
    function testFuzz_InboxRootCalculation(
        uint256 srcChain,
        address sender,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId > 0);
        vm.assume(srcChain != 0);

        // Store initial root
        bytes32 initialRoot = stagedMailbox.inboxRootPerChain(srcChain);

        // Put message in inbox
        vm.prank(COORDINATOR);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId, label, data);

        bytes32 key = stagedMailbox.getKey(srcChain, thisChain, sender, messageReceiver, sessionId, label);

        // Read message
        vm.prank(messageReceiver);
        stagedMailbox.read(srcChain, sender, sessionId, label);

        // Verify root was updated correctly
        bytes32 expectedRoot = keccak256(abi.encode(initialRoot, key, data));
        bytes32 actualRoot = stagedMailbox.inboxRootPerChain(srcChain);

        assertEq(actualRoot, expectedRoot, "Inbox root should be calculated correctly");
        assertNotEq(actualRoot, initialRoot, "Root should change after read");
    }

//    /// @dev Fuzz test for outbox root calculation accuracy
//    function testFuzz_OutboxRootCalculation(
//        uint256 destChain,
//        address receiver,
//        uint256 sessionId,
//        string calldata label,
//        bytes calldata data
//    ) public {
//        vm.assume(receiver != address(0));
//        vm.assume(sessionId > 0);
//        vm.assume(destChain != 0);
//
//        // Store initial root
//        bytes32 initialRoot = stagedMailbox.outboxRootPerChain(destChain);
//
//        // Put message in outbox
//        vm.prank(COORDINATOR);
//        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId, label, data);
//
//        bytes32 key = stagedMailbox.getKey(thisChain, destChain, messageSender, receiver, sessionId, label);
//
//        // Write message
//        vm.prank(messageSender);
//        stagedMailbox.write(destChain, receiver, sessionId, label, data);
//
//        // Verify root was updated correctly
//        bytes32 expectedRoot = keccak256(abi.encode(initialRoot, key, data));
//        bytes32 actualRoot = stagedMailbox.outboxRootPerChain(destChain);
//
//        assertEq(actualRoot, expectedRoot, "Outbox root should be calculated correctly");
//        assertNotEq(actualRoot, initialRoot, "Root should change after write");
//    }

    /// @dev Fuzz test for incremental inbox root updates with multiple messages
    function testFuzz_InboxRootIncremental(
        uint256 srcChain,
        address sender,
        uint256 sessionId1,
        uint256 sessionId2,
        bytes calldata data1,
        bytes calldata data2
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId1 > 0);
        vm.assume(sessionId2 > 0);
        vm.assume(sessionId1 != sessionId2);
        vm.assume(srcChain != 0);

        // Put two messages
        vm.startPrank(COORDINATOR);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId1, "MSG1", data1);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId2, "MSG2", data2);
        vm.stopPrank();

        bytes32 key1 = stagedMailbox.getKey(srcChain, thisChain, sender, messageReceiver, sessionId1, "MSG1");
        bytes32 key2 = stagedMailbox.getKey(srcChain, thisChain, sender, messageReceiver, sessionId2, "MSG2");

        // Read first message
        vm.prank(messageReceiver);
        stagedMailbox.read(srcChain, sender, sessionId1, "MSG1");
        bytes32 rootAfterFirst = stagedMailbox.inboxRootPerChain(srcChain);

        // Verify first root
        bytes32 expectedFirstRoot = keccak256(abi.encode(bytes32(0), key1, data1));
        assertEq(rootAfterFirst, expectedFirstRoot, "First root should match");

        // Read second message
        vm.prank(messageReceiver);
        stagedMailbox.read(srcChain, sender, sessionId2, "MSG2");
        bytes32 rootAfterSecond = stagedMailbox.inboxRootPerChain(srcChain);

        // Verify incremental root calculation
        bytes32 expectedSecondRoot = keccak256(abi.encode(expectedFirstRoot, key2, data2));
        assertEq(rootAfterSecond, expectedSecondRoot, "Second root should be incremental");
        assertNotEq(rootAfterFirst, rootAfterSecond, "Roots should differ after second read");
    }

    /// @dev Fuzz test for outbox root incremental updates with multiple messages
    function testFuzz_OutboxRootIncremental(
        uint256 destChain,
        address receiver,
        uint256 sessionId1,
        uint256 sessionId2,
        bytes calldata data1,
        bytes calldata data2
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(sessionId1 > 0);
        vm.assume(sessionId2 > 0);
        vm.assume(sessionId1 != sessionId2);
        vm.assume(destChain != 0);

        // Put two messages
        vm.startPrank(COORDINATOR);
        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId1, "MSG1", data1);
        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId2, "MSG2", data2);
        vm.stopPrank();

        bytes32 key1 = stagedMailbox.getKey(thisChain, destChain, messageSender, receiver, sessionId1, "MSG1");
        bytes32 key2 = stagedMailbox.getKey(thisChain, destChain, messageSender, receiver, sessionId2, "MSG2");

        // Write first message
        vm.prank(messageSender);
        stagedMailbox.write(destChain, receiver, sessionId1, "MSG1", data1);
        bytes32 rootAfterFirst = stagedMailbox.outboxRootPerChain(destChain);

        // Verify first root
        bytes32 expectedFirstRoot = keccak256(abi.encode(bytes32(0), key1, data1));
        assertEq(rootAfterFirst, expectedFirstRoot, "First root should match");

        // Write second message
        vm.prank(messageSender);
        stagedMailbox.write(destChain, receiver, sessionId2, "MSG2", data2);
        bytes32 rootAfterSecond = stagedMailbox.outboxRootPerChain(destChain);

        // Verify incremental root calculation
        bytes32 expectedSecondRoot = keccak256(abi.encode(expectedFirstRoot, key2, data2));
        assertEq(rootAfterSecond, expectedSecondRoot, "Second root should be incremental");
        assertNotEq(rootAfterFirst, rootAfterSecond, "Roots should differ after second write");
    }

    /// @dev Fuzz test that read properly deletes inbox storage
    function testFuzz_ReadDeletesInboxStorage(
        uint256 srcChain,
        address sender,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId > 0);

        vm.prank(COORDINATOR);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId, label, data);

        bytes32 key = stagedMailbox.getKey(srcChain, thisChain, sender, messageReceiver, sessionId, label);

        // Verify data exists before read
        assertEq(stagedMailbox.inbox(key), data, "Data should exist before read");
        assertFalse(stagedMailbox.isKeyUsed(key), "Key should not be used before read");

        vm.prank(messageReceiver);
        bytes memory retrieved = stagedMailbox.read(srcChain, sender, sessionId, label);

        // Verify storage deletion after read
        assertEq(retrieved, data, "Retrieved data should match");
        assertEq(stagedMailbox.inbox(key), "", "Inbox storage should be deleted after read");
        assertTrue(stagedMailbox.isCreatedKey(key), "Created key flag should persist");
        assertTrue(stagedMailbox.isKeyUsed(key), "Used key flag should be set");
    }

    /// @dev Fuzz test that write properly deletes outbox storage
    function testFuzz_WriteDeletesOutboxStorage(
        uint256 destChain,
        address receiver,
        uint256 sessionId,
        string calldata label,
        bytes calldata data
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(sessionId > 0);

        vm.prank(COORDINATOR);
        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId, label, data);

        bytes32 key = stagedMailbox.getKey(thisChain, destChain, messageSender, receiver, sessionId, label);

        // Verify data exists before write
        assertEq(stagedMailbox.outbox(key), data, "Data should exist before write");
        assertFalse(stagedMailbox.isKeyUsed(key), "Key should not be used before write");

        vm.prank(messageSender);
        stagedMailbox.write(destChain, receiver, sessionId, label, data);

        // Verify storage deletion after write
        assertEq(stagedMailbox.outbox(key), "", "Outbox storage should be deleted after write");
        assertTrue(stagedMailbox.isCreatedKey(key), "Created key flag should persist");
        assertTrue(stagedMailbox.isKeyUsed(key), "Used key flag should be set");
    }

    /// @dev Fuzz test that chainIDsInbox only adds each chain once
    function testFuzz_ChainIDsInboxUniqueness(
        uint256 srcChain,
        address sender,
        uint256 sessionId1,
        uint256 sessionId2,
        bytes calldata data1,
        bytes calldata data2
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId1 > 0);
        vm.assume(sessionId2 > 0);
        vm.assume(sessionId1 != sessionId2);
        vm.assume(srcChain != 0);

        // Put two messages from same source chain
        vm.startPrank(COORDINATOR);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId1, "MSG1", data1);
        stagedMailbox.putInbox(srcChain, sender, messageReceiver, sessionId2, "MSG2", data2);
        vm.stopPrank();

        // Read both messages
        vm.startPrank(messageReceiver);
        stagedMailbox.read(srcChain, sender, sessionId1, "MSG1");
        stagedMailbox.read(srcChain, sender, sessionId2, "MSG2");
        vm.stopPrank();

        // Verify only one chain ID entry exists
        assertEq(stagedMailbox.chainIDsInbox(0), srcChain, "First chain ID should match");

        // Attempting to access second element should revert (only one entry)
        vm.expectRevert();
        stagedMailbox.chainIDsInbox(1);
    }

    /// @dev Fuzz test that chainIDsOutbox only adds each chain once
    function testFuzz_ChainIDsOutboxUniqueness(
        uint256 destChain,
        address receiver,
        uint256 sessionId1,
        uint256 sessionId2,
        bytes calldata data1,
        bytes calldata data2
    ) public {
        vm.assume(receiver != address(0));
        vm.assume(sessionId1 > 0);
        vm.assume(sessionId2 > 0);
        vm.assume(sessionId1 != sessionId2);
        vm.assume(destChain != 0);

        // Put two messages to same destination chain
        vm.startPrank(COORDINATOR);
        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId1, "MSG1", data1);
        stagedMailbox.putOutbox(destChain, messageSender, receiver, sessionId2, "MSG2", data2);
        vm.stopPrank();

        // Write both messages
        vm.startPrank(messageSender);
        stagedMailbox.write(destChain, receiver, sessionId1, "MSG1", data1);
        stagedMailbox.write(destChain, receiver, sessionId2, "MSG2", data2);
        vm.stopPrank();

        // Verify only one chain ID entry exists
        assertEq(stagedMailbox.chainIDsOutbox(0), destChain, "First chain ID should match");

        // Attempting to access second element should revert (only one entry)
        vm.expectRevert();
        stagedMailbox.chainIDsOutbox(1);
    }

    /// @dev Fuzz test for root calculations across multiple different chains
    function testFuzz_MultiChainRootIsolation(
        uint256 chain1,
        uint256 chain2,
        address sender,
        uint256 sessionId1,
        uint256 sessionId2,
        bytes calldata data1,
        bytes calldata data2
    ) public {
        vm.assume(sender != address(0));
        vm.assume(sessionId1 > 0);
        vm.assume(sessionId2 > 0);
        vm.assume(chain1 != 0 && chain2 != 0);
        vm.assume(chain1 != chain2);

        // Put messages from different chains
        vm.startPrank(COORDINATOR);
        stagedMailbox.putInbox(chain1, sender, messageReceiver, sessionId1, "MSG", data1);
        stagedMailbox.putInbox(chain2, sender, messageReceiver, sessionId2, "MSG", data2);
        vm.stopPrank();

        // Read both messages
        vm.startPrank(messageReceiver);
        stagedMailbox.read(chain1, sender, sessionId1, "MSG");
        stagedMailbox.read(chain2, sender, sessionId2, "MSG");
        vm.stopPrank();

        // Verify each chain has its own root
        bytes32 root1 = stagedMailbox.inboxRootPerChain(chain1);
        bytes32 root2 = stagedMailbox.inboxRootPerChain(chain2);

        assertNotEq(root1, bytes32(0), "Chain 1 root should be set");
        assertNotEq(root2, bytes32(0), "Chain 2 root should be set");
        assertNotEq(root1, root2, "Different chains should have different roots");

        // Verify chain IDs array contains both chains
        bool foundChain1 = false;
        bool foundChain2 = false;

        if (stagedMailbox.chainIDsInbox(0) == chain1 || stagedMailbox.chainIDsInbox(0) == chain2) {
            foundChain1 = (stagedMailbox.chainIDsInbox(0) == chain1);
            foundChain2 = (stagedMailbox.chainIDsInbox(0) == chain2);
        }

        if (stagedMailbox.chainIDsInbox(1) == chain1 || stagedMailbox.chainIDsInbox(1) == chain2) {
            foundChain1 = foundChain1 || (stagedMailbox.chainIDsInbox(1) == chain1);
            foundChain2 = foundChain2 || (stagedMailbox.chainIDsInbox(1) == chain2);
        }

        assertTrue(foundChain1 && foundChain2, "Both chain IDs should be recorded");
    }
}

contract MockTarget {
    function doSomething() external pure returns (bool) {
        return true;
    }

    function fail() external pure {
        revert("Failed");
    }
}