// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { ComposeSetup } from "test/l1/setup/ComposeSetup.sol";

/// @title ComposeCommonTest
/// @notice Common test utilities that extend ComposeSetup.
///         All test contracts should inherit from this.
contract ComposeCommonTest is Test, ComposeSetup {
    /// @notice Setup function that runs before each test
    function setUp() public virtual override {
        // Call parent setup to deploy infrastructure
        ComposeSetup.setUp();
        
        // Additional test-specific setup
        vm.label(address(this), "TestContract");
    }
    
    /// @notice Helper to create a mock SP1 proof
    function _createMockSP1Proof() internal pure returns (bytes memory) {
        // Return empty bytes for now - will be replaced with actual proof structure
        return "";
    }
    
    /// @notice Helper to advance time
    function _advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }
    
    /// @notice Helper to advance blocks
    function _advanceBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }
}
