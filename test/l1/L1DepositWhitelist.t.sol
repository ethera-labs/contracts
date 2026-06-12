// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {Proxy} from "src/universal/Proxy.sol";
import {ProxyAdmin} from "src/universal/ProxyAdmin.sol";
import {L1DepositWhitelist} from "src/l1/L1DepositWhitelist.sol";
import {IL1DepositWhitelist} from "src/l1/interfaces/IL1DepositWhitelist.sol";

contract L1DepositWhitelistTest is Test {
    L1DepositWhitelist internal whitelist;
    ProxyAdmin internal proxyAdmin;

    address internal proxyAdminOwner = makeAddr("proxyAdminOwner");
    address internal defaultAdmin = makeAddr("defaultAdmin");
    address internal whitelistAdmin = makeAddr("whitelistAdmin");
    address internal operator = makeAddr("operator");
    address internal portal = makeAddr("portal");
    address internal token = makeAddr("token");

    function setUp() public {
        proxyAdmin = new ProxyAdmin(proxyAdminOwner);
        Proxy proxy = new Proxy(address(proxyAdmin));
        L1DepositWhitelist impl = new L1DepositWhitelist();

        vm.prank(proxyAdminOwner);
        proxyAdmin.upgradeAndCall(payable(address(proxy)), address(impl), abi.encodeCall(L1DepositWhitelist.initialize, (defaultAdmin, whitelistAdmin)));

        whitelist = L1DepositWhitelist(address(proxy));
    }

    function test_defaultsFalse() public view {
        assertFalse(whitelist.portalDepositAllowed(portal));
        assertFalse(whitelist.erc20DepositAllowed(portal, token));
    }

    function test_initialRoles() public view {
        assertTrue(whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(whitelist.hasRole(whitelist.DEPOSIT_WHITELIST_ROLE(), whitelistAdmin));
        assertFalse(whitelist.hasRole(whitelist.DEPOSIT_WHITELIST_ROLE(), defaultAdmin));
    }

    function test_defaultAdminCannotSetWhitelistWithoutRole() public {
        vm.prank(defaultAdmin);
        vm.expectRevert();
        whitelist.setPortalDepositAllowed(portal, true);

        vm.prank(defaultAdmin);
        vm.expectRevert();
        whitelist.setERC20DepositAllowed(portal, token, true);
    }

    function test_whitelistAdminCanSetPortalAndToken() public {
        vm.startPrank(whitelistAdmin);
        whitelist.setPortalDepositAllowed(portal, true);
        whitelist.setERC20DepositAllowed(portal, token, true);
        vm.stopPrank();

        assertTrue(whitelist.portalDepositAllowed(portal));
        assertTrue(whitelist.erc20DepositAllowed(portal, token));
    }

    function test_defaultAdminCanGrantAndRevokeWhitelistRole() public {
        bytes32 whitelistRole = whitelist.DEPOSIT_WHITELIST_ROLE();
        assertTrue(whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), defaultAdmin));

        vm.prank(defaultAdmin);
        whitelist.grantRole(whitelistRole, operator);
        assertTrue(whitelist.hasRole(whitelistRole, operator));

        vm.prank(operator);
        whitelist.setPortalDepositAllowed(portal, true);
        assertTrue(whitelist.portalDepositAllowed(portal));

        vm.prank(defaultAdmin);
        whitelist.revokeRole(whitelistRole, operator);

        vm.prank(operator);
        vm.expectRevert();
        whitelist.setPortalDepositAllowed(portal, false);
    }

    function test_zeroAddressReverts() public {
        vm.startPrank(whitelistAdmin);

        vm.expectRevert(IL1DepositWhitelist.L1DepositWhitelist_ZeroAddress.selector);
        whitelist.setPortalDepositAllowed(address(0), true);

        vm.expectRevert(IL1DepositWhitelist.L1DepositWhitelist_ZeroAddress.selector);
        whitelist.setERC20DepositAllowed(address(0), token, true);

        vm.expectRevert(IL1DepositWhitelist.L1DepositWhitelist_ZeroAddress.selector);
        whitelist.setERC20DepositAllowed(portal, address(0), true);

        vm.stopPrank();
    }
}
