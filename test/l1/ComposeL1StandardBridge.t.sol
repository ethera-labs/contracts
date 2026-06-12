// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, StdStorage, stdStorage} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Proxy} from "src/universal/Proxy.sol";
import {ProxyAdmin} from "src/universal/ProxyAdmin.sol";
import {Predeploys} from "src/libraries/Predeploys.sol";
import {ComposeL1StandardBridge} from "src/l1/ComposeL1StandardBridge.sol";

import {ICrossDomainMessenger} from "interfaces/universal/ICrossDomainMessenger.sol";
import {ISystemConfig} from "interfaces/L1/ISystemConfig.sol";
import {MockL1CrossDomainMessenger} from "test/l1/mock/MockL1CrossDomainMessenger.sol";
import {MockSuperchainConfig} from "test/l1/mock/MockSuperchainConfig.sol";
import {MockSystemConfig} from "test/l1/mock/MockSystemConfig.sol";

contract LegacyTestERC20 is ERC20 {
    constructor() ERC20("Legacy Test", "LT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ComposeL1StandardBridgeTest is Test {
    using stdStorage for StdStorage;

    StdStorage internal store;

    ComposeL1StandardBridge internal bridge;
    MockL1CrossDomainMessenger internal messenger;
    LegacyTestERC20 internal token;

    address internal proxyAdminOwner = makeAddr("proxyAdminOwner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        messenger = new MockL1CrossDomainMessenger();
        token = new LegacyTestERC20();

        MockSuperchainConfig superchainConfig = new MockSuperchainConfig();
        MockSystemConfig systemConfig = new MockSystemConfig(superchainConfig, proxyAdminOwner, 10);

        ProxyAdmin proxyAdmin = new ProxyAdmin(proxyAdminOwner);
        Proxy proxy = new Proxy(address(proxyAdmin));
        ComposeL1StandardBridge impl = new ComposeL1StandardBridge();

        vm.prank(proxyAdminOwner);
        proxyAdmin.upgradeAndCall(
            payable(address(proxy)),
            address(impl),
            abi.encodeCall(ComposeL1StandardBridge.initialize, (ICrossDomainMessenger(address(messenger)), ISystemConfig(address(systemConfig))))
        );

        bridge = ComposeL1StandardBridge(payable(address(proxy)));
        vm.deal(alice, 10 ether);
    }

    function test_allLegacyDepositSelectorsRevert() public {
        vm.startPrank(alice, alice);

        (bool receiveOk,) = address(bridge).call{value: 1 ether}("");
        assertFalse(receiveOk);

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.depositETH{value: 1 ether}(200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.depositETHTo{value: 1 ether}(bob, 200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.bridgeETH{value: 1 ether}(200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.bridgeETHTo{value: 1 ether}(bob, 200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.depositERC20(address(token), address(0xABCD), 1 ether, 200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.depositERC20To(address(token), address(0xABCD), bob, 1 ether, 200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.bridgeERC20(address(token), address(0xABCD), 1 ether, 200_000, hex"");

        vm.expectRevert(ComposeL1StandardBridge.ComposeL1StandardBridge_DepositsDisabled.selector);
        bridge.bridgeERC20To(address(token), address(0xABCD), bob, 1 ether, 200_000, hex"");

        vm.stopPrank();
    }

    function test_finalizeETHWithdrawalStillWorks() public {
        uint256 amount = 1 ether;
        uint256 bobBefore = bob.balance;

        bytes memory message = abi.encodeWithSelector(bridge.finalizeETHWithdrawal.selector, alice, bob, amount, hex"");

        (bool ok,) = messenger.relayFromOtherBridge{value: amount}(Predeploys.L2_STANDARD_BRIDGE, address(bridge), amount, message);
        assertTrue(ok);
        assertEq(bob.balance, bobBefore + amount);
    }

    function test_finalizeERC20WithdrawalStillWorksForHistoricalEscrow() public {
        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;

        token.mint(address(bridge), amount);
        store.target(address(bridge)).sig(bridge.deposits.selector).with_key(address(token)).with_key(remoteToken).checked_write(amount);

        bytes memory message = abi.encodeWithSelector(bridge.finalizeERC20Withdrawal.selector, address(token), remoteToken, alice, bob, amount, hex"");

        (bool ok,) = messenger.relayFromOtherBridge(Predeploys.L2_STANDARD_BRIDGE, address(bridge), 0, message);
        assertTrue(ok);
        assertEq(token.balanceOf(bob), amount);
        assertEq(bridge.deposits(address(token), remoteToken), 0);
    }
}
