// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

contract MockComposeL2OutputOracle {
    uint256 public proposeL2OutputCallCount;

    function proposeL2Output(bytes32, bytes32, bytes calldata) external {
        proposeL2OutputCallCount++;
    }
}