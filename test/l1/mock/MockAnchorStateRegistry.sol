// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @notice Bare-stub ASR. The portal stores this address but never calls it on the paths our
///         integration tests exercise (deposit + `authorizeBridge` + `unlockERC20` via
///         `vm.store`-faked finalize context). If a test path reaches a getter here, it reverts
///         loudly so the test writer notices.
contract MockAnchorStateRegistry {
    fallback() external {
        revert("MockAnchorStateRegistry: unimplemented call");
    }
}
