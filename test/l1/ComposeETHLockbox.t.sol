// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ComposeCommonTest} from "test/l1/setup/ComposeCommonTest.sol";
import {IOptimismPortal2 as IOptimismPortal} from "@optimism/interfaces/L1/IOptimismPortal2.sol";
import {MockPortal} from "test/l1/mock/MockPortal.sol";

/// @title ComposeETHLockboxTest
/// @notice Tests for the ComposeETHLockbox contract
contract ComposeETHLockboxTest is ComposeCommonTest {
    MockPortal internal mockPortal1;
    MockPortal internal mockPortal2;
    MockPortal internal mockPortalDifferentConfig;

    function setUp() public override {
        super.setUp();

        // Deploy mock portals with the same SuperchainConfig
        mockPortal1 = new MockPortal(composeSuperchainConfig);
        mockPortal2 = new MockPortal(composeSuperchainConfig);

        vm.deal(address(mockPortal1), 1000 ether);
        vm.deal(address(mockPortal2), 1000 ether);

        // portal with a different SuperchainConfig
        mockPortalDifferentConfig = new MockPortal(rollupSuperchainConfig);
        vm.deal(address(mockPortalDifferentConfig), 1000 ether);
    }

    // ============ Authorization Tests ============

    function test_authorizePortal_success() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortal1)))));
    }

    function test_authorizePortal_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));
    }

    function test_authorizePortal_canReauthorize() public {
        // First authorization
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortal1)))));

        // Re-authorization is idempotent (no revert)
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortal1)))));
    }

    function test_reauthorize_differentConfigPortal_canReauthorize() public {
        vm.startPrank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));
        vm.stopPrank();

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortalDifferentConfig)))));
    }

    function test_authorizePortal_withDifferentSuperchainConfig_success() public {
        assertTrue(address(mockPortalDifferentConfig.superchainConfig()) != address(composeETHLockbox.superchainConfig()));

        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortalDifferentConfig)))));
    }

    // ============ Lock Tests ============

    function test_lockETH_success() public {
        uint256 lockAmount = 10 ether;

        // Authorize portal
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        // Portal locks ETH
        vm.prank(address(mockPortal1));
        composeETHLockbox.lockETH{value: lockAmount}();

        assertEq(address(composeETHLockbox).balance, lockAmount);
    }

    function test_lockETH_revertsIfNotAuthorized() public {
        vm.prank(address(mockPortal1));
        vm.expectRevert(); // ETHLockbox_Unauthorized
        composeETHLockbox.lockETH{value: 10 ether}();
    }

    function test_differentConfigPortal_canLockETH() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        vm.prank(address(mockPortalDifferentConfig));
        composeETHLockbox.lockETH{value: 1 ether}();

        assertEq(address(composeETHLockbox).balance, 1 ether);
    }

    function test_lockETH_differentConfig_rollupPaused_Works() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        vm.prank(guardian);
        rollupSuperchainConfig.pause(address(mockPortalDifferentConfig));

        vm.prank(address(mockPortalDifferentConfig));
        composeETHLockbox.lockETH{value: 1 ether}();

        assertEq(address(composeETHLockbox).balance, 1 ether);
    }

    // ============ Unlock Tests ============

    function test_unlockETH_revertsIfNotAuthorizedPortal() public {
        vm.prank(address(mockPortal1)); // Not authorized
        vm.expectRevert(); // ETHLockbox_Unauthorized
        composeETHLockbox.unlockETH(10 ether);
    }

    function test_unlockETH_revertsIfInsufficientBalance() public {
        // Authorize portal
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        // Try to unlock more than available
        vm.prank(address(mockPortal1));
        vm.expectRevert(); // ETHLockbox_InsufficientBalance
        composeETHLockbox.unlockETH(20 ether);
    }

    function test_unlockETH_revertsWhenPaused() public {
        // Lock some ETH first
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        vm.prank(address(mockPortal1));
        composeETHLockbox.lockETH{value: 100 ether}();

        // Pause
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        vm.prank(address(mockPortal1));
        vm.expectRevert(); // ETHLockbox_Paused
        composeETHLockbox.unlockETH(10 ether);
    }

    function test_rollupPause_doesNotBlockLockETH_forDifferentConfigPortal() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        vm.prank(guardian);
        rollupSuperchainConfig.pause(address(0));

        vm.prank(address(mockPortalDifferentConfig));
        composeETHLockbox.lockETH{value: 1 ether}();

        assertEq(address(composeETHLockbox).balance, 1 ether);
    }

    // ============ Pause Tests ============

    function test_paused_returnsFalseInitially() public view {
        assertFalse(composeETHLockbox.paused());
    }

    function test_paused_returnsTrueWhenPaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        assertTrue(composeETHLockbox.paused());
    }

    function test_paused_returnsFalseAfterUnpause() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        vm.prank(guardian);
        composeSuperchainConfig.unpause(address(0));

        assertFalse(composeETHLockbox.paused());
    }

    function test_portalStillAuthorized_evenIfRollupPaused() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        vm.prank(guardian);
        rollupSuperchainConfig.pause(address(mockPortalDifferentConfig));

        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal(payable(address(mockPortalDifferentConfig)))));
    }

    function test_composePause_blocksUnlock_forDifferentConfigPortal() public {
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortalDifferentConfig))));

        vm.prank(address(mockPortalDifferentConfig));
        composeETHLockbox.lockETH{value: 10 ether}();

        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        vm.prank(address(mockPortalDifferentConfig));
        vm.expectRevert();
        composeETHLockbox.unlockETH(5 ether);
    }

    // ============ Multiple Portal Tests ============

    function test_multiplePortals_canLock() public {
        // Authorize both portals
        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal1))));

        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal(payable(address(mockPortal2))));

        // Both portals lock ETH
        vm.prank(address(mockPortal1));
        composeETHLockbox.lockETH{value: 30 ether}();

        vm.prank(address(mockPortal2));
        composeETHLockbox.lockETH{value: 40 ether}();

        assertEq(address(composeETHLockbox).balance, 70 ether);
    }
}
