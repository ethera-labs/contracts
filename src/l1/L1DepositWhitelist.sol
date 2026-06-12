// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ProxyAdminOwnedBase} from "@optimism/src/L1/ProxyAdminOwnedBase.sol";
import {ReinitializableBase} from "@optimism/src/universal/ReinitializableBase.sol";

import {IL1DepositWhitelist} from "src/l1/interfaces/IL1DepositWhitelist.sol";

/// @custom:proxied true
/// @title L1DepositWhitelist
/// @notice Shared, default-deny L1 deposit whitelist for Compose portals and ERC20 deposits.
///         `DEFAULT_ADMIN_ROLE` manages roles. `DEPOSIT_WHITELIST_ROLE` updates deposit policy.
contract L1DepositWhitelist is Initializable, ReinitializableBase, ProxyAdminOwnedBase, AccessControl, IL1DepositWhitelist {
    /// @notice Role allowed to update portal and ERC20 deposit whitelist state.
    bytes32 public constant DEPOSIT_WHITELIST_ROLE = keccak256("DEPOSIT_WHITELIST_ROLE");

    /// @notice Whether a portal's L1->L2 deposit path is allowed.
    mapping(address => bool) public portalDepositAllowed;

    /// @notice Whether an ERC20 token is allowed for a specific portal.
    mapping(address => mapping(address => bool)) public erc20DepositAllowed;

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
        erc20DepositAllowed[_portal][_token] = _allowed;
        emit ERC20DepositWhitelistSet(_portal, _token, _allowed, msg.sender);
    }
}
