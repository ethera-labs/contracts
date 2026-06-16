// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ProxyAdminOwnedBase} from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import {ReinitializableBase} from "@optimism/src/universal/ReinitializableBase.sol";

import {IL1DepositWhitelist} from "src/l1/interfaces/IL1DepositWhitelist.sol";

/// @custom:proxied true
/// @title L1DepositWhitelist
/// @notice Shared, default-deny L1 deposit whitelist for Compose portals and ERC20 deposits.
///         `DEFAULT_ADMIN_ROLE` manages roles. `DEPOSIT_WHITELIST_ROLE` updates deposit policy.
contract L1DepositWhitelist is Initializable, ReinitializableBase, ProxyAdminOwnedBase, AccessControl, IL1DepositWhitelist {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Role allowed to update portal and ERC20 deposit whitelist state.
    bytes32 public constant DEPOSIT_WHITELIST_ROLE = keccak256("DEPOSIT_WHITELIST_ROLE");

    /// @notice Role allowed to mark tokens as bridged.
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    /// @notice Whether a portal's L1->L2 deposit path is allowed.
    mapping(address => bool) public portalDepositAllowed;

    /// @notice Enumerable set of whitelisted tokens per portal.
    mapping(address => EnumerableSet.AddressSet) private whitelistedTokensByPortal;

    /// @notice Token policy per portal and token.
    mapping(address => mapping(address => TokenData)) public tokenPolicies;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0-compose
    function version() public pure returns (string memory) {
        return "1.0.0-compose";
    }

    constructor() ReinitializableBase(1) {
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _defaultAdmin   Address that can grant and revoke roles.
    /// @param _whitelistAdmin Address that can update deposit whitelist state.
    function initialize(address _defaultAdmin, address _whitelistAdmin) external reinitializer(initVersion()) {
        _assertOnlyProxyAdminOrProxyAdminOwner();
        if (_defaultAdmin == address(0) || _whitelistAdmin == address(0)) {
            revert L1DepositWhitelist_ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(DEPOSIT_WHITELIST_ROLE, _whitelistAdmin);
    }

    /// @notice Allows or blocks all L1->L2 deposit transactions for `_portal`.
    function setPortalDepositAllowed(address _portal, bool _allowed) external onlyRole(DEPOSIT_WHITELIST_ROLE) {
        if (_portal == address(0)) revert L1DepositWhitelist_ZeroAddress();
        portalDepositAllowed[_portal] = _allowed;
        emit PortalDepositWhitelistSet(_portal, _allowed, msg.sender);
    }

    /// @notice Allows or blocks `_token` deposits through `_portal`.
    function setERC20DepositAllowed(address _portal, address _token, bool _allowed) external onlyRole(DEPOSIT_WHITELIST_ROLE) {
        if (_portal == address(0) || _token == address(0)) revert L1DepositWhitelist_ZeroAddress();

        TokenData storage policy = tokenPolicies[_portal][_token];
        policy.isWhitelisted = _allowed;

        if (_allowed) {
            whitelistedTokensByPortal[_portal].add(_token);
        } else {
            whitelistedTokensByPortal[_portal].remove(_token);
        }

        emit ERC20DepositWhitelistSet(_portal, _token, _allowed, msg.sender);
    }

    /// @notice Returns the token policy for `_token` on `_portal`.
    function getTokenDetails(address _portal, address _token) external view returns (TokenData memory) {
        return tokenPolicies[_portal][_token];
    }

    /// @notice Returns enumerable list of whitelisted tokens for `_portal`.
    function getActiveTokens(address _portal) external view returns (address[] memory) {
        return whitelistedTokensByPortal[_portal].values();
    }

    /// @notice Returns whether `_token` is whitelisted for deposits through `_portal`.
    function erc20DepositAllowed(address portal, address token) external view returns (bool) {
        return tokenPolicies[portal][token].isWhitelisted;
    }

    /// @notice Marks `_token` as bridged through `_portal` (idempotent).
    /// @dev Only callable by the portal itself (system-internal) or role holders.
    function markTokenAsL2Wrapped(address _portal, address _token) external {
        if (_portal == address(0) || _token == address(0)) revert L1DepositWhitelist_ZeroAddress();

        bool isPortal = msg.sender == _portal;
        bool hasRole = hasRole(BRIDGE_ROLE, msg.sender);
        if (!isPortal && !hasRole) revert L1DepositWhitelist_Unauthorized();

        tokenPolicies[_portal][_token].isL2Wrapped = true;
    }
}
