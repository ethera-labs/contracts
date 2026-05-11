// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ComposeCommonTest } from "test/l1/setup/ComposeCommonTest.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { ComposeERC20Lockbox } from "src/l1/ComposeERC20Lockbox.sol";
import { IComposeERC20Lockbox } from "src/l1/interfaces/IComposeERC20Lockbox.sol";
import { IComposePortal } from "src/l1/interfaces/IComposePortal.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Proxy } from "src/universal/Proxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockComposePortal {
    address public l2Sender = 0x000000000000000000000000000000000000dEaD;

    function setL2Sender(address _s) external {
        l2Sender = _s;
    }

    function pushAndLock(IComposeERC20Lockbox _lockbox, address _token, uint256 _amount) external {
        ERC20(_token).transfer(address(_lockbox), _amount);
        _lockbox.lockERC20(_token, _amount);
    }

    function unlock(IComposeERC20Lockbox _lockbox, address _token, uint256 _amount, address _to) external {
        _lockbox.unlockERC20(_token, _amount, _to);
    }
}

contract ComposeERC20LockboxTest is ComposeCommonTest {
    ComposeERC20Lockbox internal erc20Lockbox;
    MockComposePortal internal portal1;
    MockComposePortal internal portal2;
    MockERC20 internal tokenM1;

    function setUp() public override {
        super.setUp();

        portal1 = new MockComposePortal();
        portal2 = new MockComposePortal();

        tokenM1 = new MockERC20("M1 Token", "M1");

        ComposeERC20Lockbox impl = new ComposeERC20Lockbox();
        Proxy proxy = new Proxy(address(composeProxyAdmin));

        IComposePortal[] memory portals = new IComposePortal[](2);
        portals[0] = IComposePortal(address(portal1));
        portals[1] = IComposePortal(address(portal2));

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy)),
            address(impl),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, portals))
        );

        erc20Lockbox = ComposeERC20Lockbox(address(proxy));
    }

    function test_authorizePortal_success() public {
        MockComposePortal newPortal = new MockComposePortal();

        vm.prank(proxyAdminOwner);
        erc20Lockbox.authorizePortal(IComposePortal(address(newPortal)));

        assertTrue(erc20Lockbox.authorizedPortals(IComposePortal(address(newPortal))));
    }

    function test_authorizePortal_revertsIfNotOwner() public {
        MockComposePortal newPortal = new MockComposePortal();
        vm.prank(alice);
        vm.expectRevert();
        erc20Lockbox.authorizePortal(IComposePortal(address(newPortal)));
    }

    function test_authorizePortal_revertsOnZeroAddress() public {
        vm.prank(proxyAdminOwner);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.authorizePortal(IComposePortal(address(0)));
    }

    function test_lockERC20_success() public {
        uint256 lockAmount = 1000e18;

        tokenM1.mint(address(portal1), lockAmount);
        portal1.pushAndLock(erc20Lockbox, address(tokenM1), lockAmount);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), lockAmount);
        assertEq(erc20Lockbox.totalDeposited(address(tokenM1)), lockAmount);
    }

    function test_lockERC20_revertsIfNotAuthorized() public {
        tokenM1.mint(address(this), 100e18);
        tokenM1.transfer(address(erc20Lockbox), 100e18);

        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Unauthorized.selector);
        erc20Lockbox.lockERC20(address(tokenM1), 100e18);
    }

    function test_lockERC20_revertsOnZeroAmount() public {
        vm.prank(address(portal1));
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAmount.selector);
        erc20Lockbox.lockERC20(address(tokenM1), 0);
    }

    function test_lockERC20_revertsOnZeroToken() public {
        vm.prank(address(portal1));
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        erc20Lockbox.lockERC20(address(0), 100e18);
    }

    function test_lockERC20_revertsIfTokensNotPushed() public {
        // Portal calls lockERC20 without first pushing tokens; invariant check fails.
        vm.prank(address(portal1));
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_InsufficientBalance.selector);
        erc20Lockbox.lockERC20(address(tokenM1), 100e18);
    }

    function test_lockERC20_worksWhilePaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        tokenM1.mint(address(portal1), 100e18);
        portal1.pushAndLock(erc20Lockbox, address(tokenM1), 100e18);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 100e18);
    }

    function _lockThroughPortal(MockComposePortal _p, uint256 _amount) internal {
        tokenM1.mint(address(_p), _amount);
        _p.pushAndLock(erc20Lockbox, address(tokenM1), _amount);
    }

    function test_unlockERC20_success() public {
        _lockThroughPortal(portal1, 1000e18);

        // Portal must be inside a finalize context.
        portal2.setL2Sender(alice);
        portal2.unlock(erc20Lockbox, address(tokenM1), 400e18, bob);

        assertEq(tokenM1.balanceOf(bob), 400e18);
        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 600e18);
        assertEq(erc20Lockbox.totalDeposited(address(tokenM1)), 600e18);
    }

    function test_unlockERC20_revertsIfNotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Unauthorized.selector);
        erc20Lockbox.unlockERC20(address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsIfNotInFinalize() public {
        _lockThroughPortal(portal1, 100e18);

        // portal1.l2Sender still DEFAULT — not in finalize.
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_NotInFinalize.selector);
        portal1.unlock(erc20Lockbox, address(tokenM1), 50e18, alice);
    }

    function test_unlockERC20_revertsIfInsufficientAccounting() public {
        portal1.setL2Sender(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_InsufficientBalance.selector);
        portal1.unlock(erc20Lockbox, address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsWhenPaused() public {
        _lockThroughPortal(portal1, 1000e18);

        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));

        portal1.setL2Sender(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_Paused.selector);
        portal1.unlock(erc20Lockbox, address(tokenM1), 100e18, alice);
    }

    function test_unlockERC20_revertsOnZeroAmount() public {
        portal1.setL2Sender(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAmount.selector);
        portal1.unlock(erc20Lockbox, address(tokenM1), 0, alice);
    }

    function test_unlockERC20_revertsOnZeroRecipient() public {
        _lockThroughPortal(portal1, 100e18);
        portal1.setL2Sender(alice);
        vm.expectRevert(IComposeERC20Lockbox.ERC20Lockbox_ZeroAddress.selector);
        portal1.unlock(erc20Lockbox, address(tokenM1), 50e18, address(0));
    }

    function test_crossRollup_lockViaPortal1_unlockViaPortal2() public {
        _lockThroughPortal(portal1, 5000e18);

        portal2.setL2Sender(alice);
        portal2.unlock(erc20Lockbox, address(tokenM1), 2000e18, bob);

        assertEq(tokenM1.balanceOf(bob), 2000e18);
        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 3000e18);
    }

    function test_paused_returnsFalseInitially() public view {
        assertFalse(erc20Lockbox.paused());
    }

    function test_paused_returnsTrueWhenPaused() public {
        vm.prank(guardian);
        composeSuperchainConfig.pause(address(0));
        assertTrue(erc20Lockbox.paused());
    }

    function test_multipleTokens_independentBalances() public {
        MockERC20 tokenM2 = new MockERC20("M2 Token", "M2");

        _lockThroughPortal(portal1, 500e18);

        tokenM2.mint(address(portal2), 300e18);
        portal2.pushAndLock(erc20Lockbox, address(tokenM2), 300e18);

        assertEq(tokenM1.balanceOf(address(erc20Lockbox)), 500e18);
        assertEq(tokenM2.balanceOf(address(erc20Lockbox)), 300e18);

        portal2.setL2Sender(alice);
        portal2.unlock(erc20Lockbox, address(tokenM1), 200e18, alice);

        assertEq(tokenM1.balanceOf(alice), 200e18);
        assertEq(tokenM2.balanceOf(address(erc20Lockbox)), 300e18);
    }

    function test_migrateLiquidity_success() public {
        _lockThroughPortal(portal1, 1000e18);

        ComposeERC20Lockbox impl2 = new ComposeERC20Lockbox();
        Proxy proxy2 = new Proxy(address(composeProxyAdmin));
        IComposePortal[] memory emptyPortals = new IComposePortal[](0);
        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy2)),
            address(impl2),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, emptyPortals))
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
        IComposePortal[] memory emptyPortals = new IComposePortal[](0);
        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy2)),
            address(impl2),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, emptyPortals))
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
