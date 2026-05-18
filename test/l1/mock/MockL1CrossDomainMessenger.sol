// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @notice Minimal L1 `CrossDomainMessenger` mock. Captures the last `sendMessage` call so tests
///         can assert target + selector + args, and exposes `xDomainMessageSender` plus a setter
///         so finalize-path tests can simulate messenger-gated calls from `otherBridge`.
contract MockL1CrossDomainMessenger {
    address public xDomainMessageSender;

    struct Sent {
        address target;
        bytes message;
        uint32 minGasLimit;
        uint256 value;
    }

    Sent public lastSent;
    uint256 public callCount;

    function lastMessage() external view returns (bytes memory) {
        return lastSent.message;
    }

    event SendMessageCalled(address indexed target, bytes message, uint32 minGasLimit, uint256 value);

    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable {
        lastSent = Sent({ target: _target, message: _message, minGasLimit: _minGasLimit, value: msg.value });
        callCount++;
        emit SendMessageCalled(_target, _message, _minGasLimit, msg.value);
    }

    function setXDomainMessageSender(address _sender) external {
        xDomainMessageSender = _sender;
    }

    /// @notice Relays a message as if it came from `_sender` on the other chain. Sets
    ///         `xDomainMessageSender`, calls `_target.call{value}(_message)`, then clears.
    /// @dev Used by finalize-path tests to drive `onlyOtherBridge`-gated functions.
    function relayFromOtherBridge(
        address _sender,
        address _target,
        uint256 _value,
        bytes calldata _message
    )
        external
        payable
        returns (bool ok, bytes memory ret)
    {
        xDomainMessageSender = _sender;
        (ok, ret) = _target.call{ value: _value }(_message);
        xDomainMessageSender = address(0);
    }

    receive() external payable { }
}
