// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISemver} from "@optimism/interfaces/universal/ISemver.sol";

interface IL1DepositWhitelist is ISemver {
    /// @notice Token policy struct.
    struct TokenData {
        bool isWhitelisted;
        bool isL2Wrapped;
    }

    error L1DepositWhitelist_ZeroAddress();
    error L1DepositWhitelist_Unauthorized();

    event PortalDepositWhitelistSet(address indexed portal, bool allowed, address indexed setter);
    event ERC20DepositWhitelistSet(address indexed portal, address indexed token, bool allowed, address indexed setter);

    function DEPOSIT_WHITELIST_ROLE() external view returns (bytes32);
    function BRIDGE_ROLE() external view returns (bytes32);
    function initialize(address defaultAdmin, address whitelistAdmin) external;
    function portalDepositAllowed(address portal) external view returns (bool);
    function erc20DepositAllowed(address portal, address token) external view returns (bool);
    function setPortalDepositAllowed(address portal, bool allowed) external;
    function setERC20DepositAllowed(address portal, address token, bool allowed) external;
    function markTokenAsL2Wrapped(address portal, address token) external;
}
