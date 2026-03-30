// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ComposeCommonTest } from "test/setup/ComposeCommonTest.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { ComposeERC20Lockbox } from "src/ComposeERC20Lockbox.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Proxy } from "src/universal/Proxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ComposeERC20LockboxTest is ComposeCommonTest {
    ComposeERC20Lockbox internal erc20Lockbox;
    address internal bridge1;
    address internal bridge2;
    MockERC20 internal tokenM1;

    function setUp() public override {
        super.setUp();

        bridge1 = makeAddr("bridge1");
        bridge2 = makeAddr("bridge2");

        tokenM1 = new MockERC20("M1 Token", "M1");

        ComposeERC20Lockbox impl = new ComposeERC20Lockbox();
        Proxy proxy = new Proxy(address(composeProxyAdmin));

        address[] memory bridges = new address[](2);
        bridges[0] = bridge1;
        bridges[1] = bridge2;

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy)),
            address(impl),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, bridges))
        );

        erc20Lockbox = ComposeERC20Lockbox(address(proxy));
    }

    function test_authorizeBridge_success() public {
        address newBridge = makeAddr("newBridge");

        vm.prank(proxyAdminOwner);
        erc20Lockbox.authorizeBridge(newBridge);

        assertTrue(erc20Lockbox.authorizedBridges(newBridge));
    }

    function test_authorizeBridge_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        erc20Lockbox.authorizeBridge(makeAddr("newBridge"));
    }

    function test_authorizeBridge_revertsOnZeroAddress() public {
        vm.prank(proxyAdminOwner);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.authorizeBridge(address(0));
    }

    function test_lockERC20_success() public {
        uint256 lockAmount = 1000e18;

        tokenM1.mint(alice, lockAmount);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), lockAmount);

        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, lockAmount);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), lockAmount);
        assertEq(tokenM1.balanceOf(alice), 0);
    }

    function test_lockERC20_revertsIfNotAuthorized() public {
        address rando = makeAddr("rando");
        tokenM1.mint(alice, 100e18);

        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 100e18);

        vm.prank(rando);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Unauthorized.selector);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 100e18);
    }

    function test_lockERC20_revertsOnZeroAmount() public {
        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAmount.selector);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 0);
    }

    function test_lockERC20_revertsOnZeroToken() public {
        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.lockERC20(address(0), alice, 100e18);
    }

    function test_lockERC20_revertsOnZeroFrom() public {
        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.lockERC20(address(tokenM1), address(0), 100e18);
    }

    function test_unlockERC20_success() public {
        uint256 lockAmount = 1000e18;
        uint256 unlockAmount = 400e18;

        tokenM1.mint(alice, lockAmount);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), lockAmount);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, lockAmount);

        vm.prank(bridge2);
        erc20Lockbox.unlockERC20(address(tokenM1), unlockAmount, bob);

        assertEq(tokenM1.balanceOf(bob), unlockAmount);
        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), lockAmount - unlockAmount);
    }

    function test_unlockERC20_revertsIfNotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Unauthorized.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsIfInsufficientBalance() public {
        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_InsufficientBalance.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsWhenPaused() public {
        tokenM1.mint(alice, 1000e18);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 1000e18);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 1000e18);

        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Paused.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsOnZeroAmount() public {
        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAmount.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 0, alice);
    }

    function test_unlockERC20_revertsOnZeroRecipient() public {
        tokenM1.mint(alice, 100e18);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 100e18);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 100e18);

        vm.prank(bridge1);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 50e18, address(0));
    }

    function test_crossRollup_lockViaBridge1_unlockViaBridge2() public {
        uint256 depositAmount = 5000e18;
        tokenM1.mint(alice, depositAmount);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), depositAmount);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, depositAmount);

        uint256 withdrawAmount = 2000e18;
        vm.prank(bridge2);
        erc20Lockbox.unlockERC20(address(tokenM1), withdrawAmount, bob);

        assertEq(tokenM1.balanceOf(bob), withdrawAmount);
        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), depositAmount - withdrawAmount);
    }

    function test_paused_returnsFalseInitially() public view {
        assertFalse(erc20Lockbox.paused());
    }

    function test_paused_returnsTrueWhenPaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        assertTrue(erc20Lockbox.paused());
    }

    function test_lockERC20_worksWhilePaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        tokenM1.mint(alice, 100e18);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 100e18);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 100e18);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 100e18);
    }

    function test_multipleTokens_independentBalances() public {
        MockERC20 tokenM2 = new MockERC20("M2 Token", "M2");

        tokenM1.mint(alice, 500e18);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 500e18);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 500e18);

        tokenM2.mint(bob, 300e18);
        vm.prank(bob);
        tokenM2.approve(address(erc20Lockbox), 300e18);
        vm.prank(bridge2);
        erc20Lockbox.lockERC20(address(tokenM2), bob, 300e18);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 500e18);
        assertEq(tokenM2.balanceOf(address(erc20Lockbox)), 300e18);

        vm.prank(bridge2);
        erc20Lockbox.unlockERC20(address(tokenM1), 200e18, alice);

        assertEq(tokenM1.balanceOf(alice), 200e18);
        assertEq(tokenM2.balanceOf(address(erc20Lockbox)), 300e18);
    }

    function test_migrateLiquidity_success() public {
        tokenM1.mint(alice, 1000e18);
        vm.prank(alice);
        tokenM1.approve(address(erc20Lockbox), 1000e18);
        vm.prank(bridge1);
        erc20Lockbox.lockERC20(address(tokenM1), alice, 1000e18);

        ComposeERC20Lockbox impl2 = new ComposeERC20Lockbox();
        Proxy proxy2 = new Proxy(address(composeProxyAdmin));
        address[] memory emptyBridges = new address[](0);
        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy2)),
            address(impl2),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, emptyBridges))
        );
        ComposeERC20Lockbox lockbox2 = ComposeERC20Lockbox(address(proxy2));

        vm.prank(proxyAdminOwner);
        lockbox2.authorizeLockbox(IComposeERC20Lockbox(address(erc20Lockbox)));

        vm.prank(proxyAdminOwner);
        erc20Lockbox.migrateLiquidity(address(tokenM1), IComposeERC20Lockbox(address(lockbox2)));

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 0);
        assertEq(tokenM1.balanceOf(address(lockbox2)), 1000e18);
    }

    function test_migrateLiquidity_revertsIfNotOwner() public {
        ComposeERC20Lockbox impl2 = new ComposeERC20Lockbox();
        Proxy proxy2 = new Proxy(address(composeProxyAdmin));
        address[] memory emptyBridges = new address[](0);
        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy2)),
            address(impl2),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, emptyBridges))
        );

        vm.prank(alice);
        vm.expectRevert();
        erc20Lockbox.migrateLiquidity(address(tokenM1), IComposeERC20Lockbox(address(proxy2)));
    }

    function test_receiveLiquidity_revertsIfNotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Unauthorized.selector);
        erc20Lockbox.receiveLiquidity(address(tokenM1), 100e18);
    }
}
