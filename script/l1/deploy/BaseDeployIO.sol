// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { CommonBase } from "forge-std/Base.sol";

/// @title BaseDeployIO
/// @notice Base contract for all Deploy<X>Input and Deploy<X>Output contracts.
/// @dev Provides access to cheatcodes via CommonBase. All Input/Output structs should
///      be defined in contracts that inherit from this base to maintain consistency.
abstract contract BaseDeployIO is CommonBase { }
