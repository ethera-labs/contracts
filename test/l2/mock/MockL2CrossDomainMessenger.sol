// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.18;

contract MockL2CrossDomainMessenger {
    address public xDomainMessageSender;

    struct Sent {
        address target;
        bytes message;
        uint32 minGasLimit;
        uint256 value;
    }

    Sent public lastSent;
    uint256 public callCount;

    event SendMessageCalled(address indexed target, bytes message, uint32 minGasLimit, uint256 value);

    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable {
        lastSent = Sent({target: _target, message: _message, minGasLimit: _minGasLimit, value: msg.value});
        callCount++;
        emit SendMessageCalled(_target, _message, _minGasLimit, msg.value);
    }

    function lastMessage() external view returns (bytes memory) {
        return lastSent.message;
    }

    function setXDomainMessageSender(address _sender) external {
        xDomainMessageSender = _sender;
    }

    function relayFromOtherBridge(address _sender, address _target, uint256 _value, bytes calldata _message)
        external
        payable
        returns (bool ok, bytes memory ret)
    {
        xDomainMessageSender = _sender;
        (ok, ret) = _target.call{value: _value}(_message);
        xDomainMessageSender = address(0);
    }

    receive() external payable {}
}
