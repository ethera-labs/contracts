// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @title IComposePortal
/// @notice Minimal surface the ComposeERC20Lockbox needs from the ComposePortal
///         to validate finalize-context unlocks.
interface IComposePortal {
    function l2Sender() external view returns (address);
}
