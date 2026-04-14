// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { StdStorage, stdStorage } from "forge-std/Test.sol";
import { ComposeCommonTest } from "test/setup/ComposeCommonTest.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { ComposePortal } from "src/ComposePortal.sol";
import { ComposeL1Bridge, IComposePortalERC20 } from "src/ComposeL1Bridge.sol";
import { ComposeERC20Lockbox } from "src/ComposeERC20Lockbox.sol";
import { IComposePortal } from "src/interfaces/IComposePortal.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";
import { ISystemConfig } from "interfaces/L1/ISystemConfig.sol";
import { IAnchorStateRegistry } from "interfaces/dispute/IAnchorStateRegistry.sol";
import { ICrossDomainMessenger } from "interfaces/universal/ICrossDomainMessenger.sol";
import { ISuperchainConfig } from "interfaces/L1/ISuperchainConfig.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { MockSystemConfig } from "test/mock/MockSystemConfig.sol";
import { MockAnchorStateRegistry } from "test/mock/MockAnchorStateRegistry.sol";
import { MockL1CrossDomainMessenger } from "test/mock/MockL1CrossDomainMessenger.sol";
import { Constants } from "src/libraries/Constants.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @title ComposeIntegrationSetup
/// @notice Full L1 wiring for integration tests:
///           - Real `ComposePortal` behind a proxy (parent init + `initializeCompose`)
///           - Real `ComposeL1Bridge` behind a proxy
///           - Real `ComposeERC20Lockbox` behind a proxy
///           - Re-uses `composeETHLockbox` deployed by `ComposeSetup`
///           - Mocks: `SystemConfig`, `AnchorStateRegistry`, `L1CrossDomainMessenger`
contract ComposeIntegrationSetup is ComposeCommonTest {
    using stdStorage for StdStorage;

    ComposePortal public portal;
    ComposeL1Bridge public bridge;
    ComposeERC20Lockbox public erc20Lockbox;

    MockSystemConfig public systemConfig;
    MockAnchorStateRegistry public asr;
    MockL1CrossDomainMessenger public messenger;

    MockERC20 public token;

    uint256 public constant PROOF_MATURITY_DELAY = 7 days;
    uint256 public constant L2_CHAIN_ID = 84_532;

    event ETHDepositInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ETHBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ETHWithdrawalFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ERC20DepositInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );
    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );
    event ERC20WithdrawalFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );
    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );
    event ERC20TransactionUnlocked(
        address indexed localToken,
        address indexed to,
        uint256 amount,
        address indexed bridge
    );

    function setUp() public virtual override {
        super.setUp();

        systemConfig = new MockSystemConfig(composeSuperchainConfig, guardian, L2_CHAIN_ID);
        asr          = new MockAnchorStateRegistry();
        messenger    = new MockL1CrossDomainMessenger();
        vm.deal(address(messenger), 1000 ether);

        portal = _deployPortal();
        erc20Lockbox = _deployErc20Lockbox(portal);

        vm.prank(proxyAdminOwner);
        composeETHLockbox.authorizePortal(IOptimismPortal2(payable(address(portal))));

        bridge = _deployBridge(portal, erc20Lockbox);

        vm.prank(proxyAdminOwner);
        portal.authorizeBridge(address(bridge));

        token = new MockERC20("Test", "TST");
        token.mint(alice, 1_000e18);
        token.mint(bob, 1_000e18);

        vm.label(address(portal),       "ComposePortal");
        vm.label(address(bridge),       "ComposeL1Bridge");
        vm.label(address(erc20Lockbox), "ComposeERC20Lockbox");
        vm.label(address(systemConfig), "MockSystemConfig");
        vm.label(address(asr),          "MockAnchorStateRegistry");
        vm.label(address(messenger),    "MockL1CrossDomainMessenger");
        vm.label(address(token),        "MockERC20");
    }

    function test_eth_bridgeETH_sendsMessengerMessageWithValue() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 1 ether;
        uint32 minGas = 200_000;
        bytes memory extra = hex"1234";

        bytes memory expectedMessage = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            alice,
            amount,
            extra
        );

        vm.expectCall(
            address(messenger),
            amount,
            abi.encodeCall(ICrossDomainMessenger.sendMessage, (fakeL2Bridge, expectedMessage, minGas))
        );

        vm.prank(alice, alice);
        bridge.bridgeETH{ value: amount }(minGas, extra);

        (, , uint32 sentMinGas, uint256 sentValue) = messenger.lastSent();
        assertEq(sentMinGas, minGas);
        assertEq(sentValue, amount);
        assertEq(messenger.callCount(), 1);
    }

    function test_eth_bridgeETH_emitsDepositAndBridgeInit() public {
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(address(0xBEEF));

        uint256 amount = 1 ether;
        uint32 minGas = 200_000;
        bytes memory extra = hex"1234";

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHDepositInitiated(alice, alice, amount, extra);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHBridgeInitiated(alice, alice, amount, extra);

        vm.prank(alice, alice);
        bridge.bridgeETH{ value: amount }(minGas, extra);
    }

    function test_eth_bridgeETHTo_routesToRecipient() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 1 ether;
        uint32 minGas = 200_000;
        bytes memory extra = hex"cafe";

        bytes memory expectedMessage = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            bob,
            amount,
            extra
        );

        vm.expectCall(
            address(messenger),
            amount,
            abi.encodeCall(ICrossDomainMessenger.sendMessage, (fakeL2Bridge, expectedMessage, minGas))
        );

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHDepositInitiated(alice, bob, amount, extra);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHBridgeInitiated(alice, bob, amount, extra);

        vm.prank(alice);
        bridge.bridgeETHTo{ value: amount }(bob, minGas, extra);
    }

    function test_eth_receive_fromEOA_bridgesToSelf() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 0.5 ether;
        uint32 minGas = 200_000;

        bytes memory expectedMessage = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            alice,
            amount,
            bytes("")
        );

        vm.expectCall(
            address(messenger),
            amount,
            abi.encodeCall(ICrossDomainMessenger.sendMessage, (fakeL2Bridge, expectedMessage, minGas))
        );

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHDepositInitiated(alice, alice, amount, bytes(""));

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHBridgeInitiated(alice, alice, amount, bytes(""));

        vm.prank(alice, alice);
        (bool ok, ) = address(bridge).call{ value: amount }("");
        assertTrue(ok);
    }

    function test_eth_finalize_succeeds_viaMessengerFromOtherBridge() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 1 ether;
        bytes memory extra = hex"dead";

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            bob,
            amount,
            extra
        );

        uint256 bobBefore = bob.balance;

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), amount, message);
        assertTrue(ok);

        assertEq(bob.balance, bobBefore + amount);
    }

    function test_erc20_bridgeERC20_pullsTokensAndLocks() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 100e18;
        vm.prank(alice);
        token.approve(address(bridge), amount);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 lbBefore = token.balanceOf(address(erc20Lockbox));
        uint256 totBefore = erc20Lockbox.totalDeposited(address(token));

        vm.prank(alice);
        bridge.bridgeERC20To(address(token), address(0xABCD), bob, amount, 200_000, hex"11");

        assertEq(token.balanceOf(alice), aliceBefore - amount);
        assertEq(token.balanceOf(address(erc20Lockbox)), lbBefore + amount);
        assertEq(erc20Lockbox.totalDeposited(address(token)), totBefore + amount);
        assertEq(token.balanceOf(address(portal)), 0);
        assertEq(token.balanceOf(address(bridge)), 0);
    }

    function test_erc20_bridgeERC20_emitsDepositAndBridgeInit() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;
        bytes memory extra = hex"11";

        vm.prank(alice);
        token.approve(address(bridge), amount);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ERC20DepositInitiated(address(token), remoteToken, alice, bob, amount, extra);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ERC20BridgeInitiated(address(token), remoteToken, alice, bob, amount, extra);

        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, extra);
    }

    function test_erc20_bridgeERC20_sendsMessageWithSwappedArgs() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;
        uint32 minGas = 200_000;
        bytes memory extra = hex"11";

        vm.prank(alice);
        token.approve(address(bridge), amount);

        bytes memory packedExtra = abi.encode(token.name(), token.symbol(), token.decimals(), extra);

        bytes memory expectedMessage = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            remoteToken,
            address(token),
            alice,
            bob,
            amount,
            packedExtra
        );

        vm.expectCall(
            address(messenger),
            0,
            abi.encodeCall(ICrossDomainMessenger.sendMessage, (fakeL2Bridge, expectedMessage, minGas))
        );

        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, minGas, extra);

        (, , uint32 sentMinGas, uint256 sentValue) = messenger.lastSent();
        assertEq(sentMinGas, minGas);
        assertEq(sentValue, 0);
        assertEq(messenger.callCount(), 1);
    }

    function test_erc20_bridgeERC20_packsMetadataIntoExtraData() public {
        bytes memory userExtra = hex"deadbeef";
        bytes memory packedExtra = _doBridgeAndGetPackedExtra(userExtra);

        (string memory name_, string memory symbol_, uint8 decimals_, bytes memory userBytes) =
            abi.decode(packedExtra, (string, string, uint8, bytes));

        assertEq(name_, token.name());
        assertEq(symbol_, token.symbol());
        assertEq(decimals_, token.decimals());
        assertEq(keccak256(userBytes), keccak256(userExtra));
    }

    function _doBridgeAndGetPackedExtra(bytes memory userExtra) internal returns (bytes memory) {
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(address(0xBEEF));

        uint256 amount = 100e18;
        vm.prank(alice);
        token.approve(address(bridge), amount);

        vm.prank(alice);
        bridge.bridgeERC20To(address(token), address(0xABCD), bob, amount, 200_000, userExtra);

        bytes memory sentMessage = messenger.lastMessage();
        bytes memory args = new bytes(sentMessage.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = sentMessage[i + 4];
        }
        (, , , , , bytes memory packed) =
            abi.decode(args, (address, address, address, address, uint256, bytes));
        return packed;
    }

    function test_erc20_finalize_succeeds_releasesFromLockbox() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;

        vm.prank(alice);
        token.approve(address(bridge), amount);
        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, hex"");

        _enterFinalize(alice);

        uint256 bobBefore = token.balanceOf(bob);
        uint256 lbBefore = token.balanceOf(address(erc20Lockbox));
        uint256 totBefore = erc20Lockbox.totalDeposited(address(token));

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            address(token),
            remoteToken,
            alice,
            bob,
            amount,
            hex""
        );

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), 0, message);
        assertTrue(ok);

        assertEq(token.balanceOf(bob), bobBefore + amount);
        assertEq(token.balanceOf(address(erc20Lockbox)), lbBefore - amount);
        assertEq(erc20Lockbox.totalDeposited(address(token)), totBefore - amount);
    }

    function test_erc20_finalize_emitsWithdrawalFinalizedAndBridgeFinalized() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;
        bytes memory extra = hex"dead";

        vm.prank(alice);
        token.approve(address(bridge), amount);
        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, hex"");

        _enterFinalize(alice);

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            address(token),
            remoteToken,
            alice,
            bob,
            amount,
            extra
        );

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ERC20WithdrawalFinalized(address(token), remoteToken, alice, bob, amount, extra);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ERC20BridgeFinalized(address(token), remoteToken, alice, bob, amount, extra);

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), 0, message);
        assertTrue(ok);
    }

    function test_erc20_finalize_emitsERC20TransactionUnlocked_onPortal() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;

        vm.prank(alice);
        token.approve(address(bridge), amount);
        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, hex"");

        _enterFinalize(alice);

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            address(token),
            remoteToken,
            alice,
            bob,
            amount,
            hex""
        );

        vm.expectEmit(true, true, true, true, address(portal));
        emit ERC20TransactionUnlocked(address(token), bob, amount, address(bridge));

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), 0, message);
        assertTrue(ok);
    }

    function test_flow_ethRoundTrip_preservesETHLockboxBalance() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 1 ether;
        uint256 lbBefore = address(composeETHLockbox).balance;

        vm.deal(alice, amount);
        vm.prank(alice, alice);
        portal.depositTransaction{ value: amount }(alice, amount, 200_000, false, hex"");

        assertEq(address(composeETHLockbox).balance, lbBefore + amount);

        vm.prank(address(portal));
        composeETHLockbox.unlockETH(amount);

        vm.prank(address(portal));
        (bool fundOk, ) = address(messenger).call{ value: amount }("");
        assertTrue(fundOk);

        _enterFinalize(alice);

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            bob,
            amount,
            hex""
        );

        uint256 bobBefore = bob.balance;
        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), amount, message);
        assertTrue(ok);

        assertEq(address(composeETHLockbox).balance, lbBefore);
        assertEq(bob.balance, bobBefore + amount);
    }

    function test_flow_erc20RoundTrip_preservesAccounting() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        address remoteToken = address(0xABCD);
        uint256 amount = 100e18;

        uint256 lbBefore = token.balanceOf(address(erc20Lockbox));
        uint256 totBefore = erc20Lockbox.totalDeposited(address(token));
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        token.approve(address(bridge), amount);
        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, hex"");

        _enterFinalize(alice);

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            address(token),
            remoteToken,
            alice,
            bob,
            amount,
            hex""
        );

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), 0, message);
        assertTrue(ok);

        assertEq(token.balanceOf(address(erc20Lockbox)), lbBefore);
        assertEq(erc20Lockbox.totalDeposited(address(token)), totBefore);
        assertEq(token.balanceOf(alice), aliceBefore - amount);
        assertEq(token.balanceOf(bob), bobBefore + amount);
    }

    function test_flow_erc20_multipleTokens_independentAccounting() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        MockERC20 tokenB = new MockERC20("TokenB", "TB");
        tokenB.mint(alice, 1_000e18);

        uint256 amountA = 100e18;
        uint256 amountB = 250e18;
        address remoteA = address(0xAAAA);
        address remoteB = address(0xBBBB);

        vm.prank(alice);
        token.approve(address(bridge), amountA);
        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteA, bob, amountA, 200_000, hex"");

        vm.prank(alice);
        tokenB.approve(address(bridge), amountB);
        vm.prank(alice);
        bridge.bridgeERC20To(address(tokenB), remoteB, bob, amountB, 200_000, hex"");

        assertEq(erc20Lockbox.totalDeposited(address(token)), amountA);
        assertEq(erc20Lockbox.totalDeposited(address(tokenB)), amountB);
        assertEq(token.balanceOf(address(erc20Lockbox)), amountA);
        assertEq(tokenB.balanceOf(address(erc20Lockbox)), amountB);

        _enterFinalize(alice);

        bytes memory messageA = abi.encodeWithSelector(
            bridge.finalizeBridgeERC20.selector,
            address(token),
            remoteA,
            alice,
            bob,
            amountA,
            hex""
        );
        (bool okA, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), 0, messageA);
        assertTrue(okA);

        assertEq(erc20Lockbox.totalDeposited(address(token)), 0);
        assertEq(token.balanceOf(address(erc20Lockbox)), 0);

        assertEq(erc20Lockbox.totalDeposited(address(tokenB)), amountB);
        assertEq(tokenB.balanceOf(address(erc20Lockbox)), amountB);
        assertEq(tokenB.balanceOf(bob), 0);
    }

    function test_eth_finalize_emitsWithdrawalFinalizedAndBridgeFinalized() public {
        address fakeL2Bridge = address(0xBEEF);
        vm.prank(proxyAdminOwner);
        bridge.setOtherBridge(fakeL2Bridge);

        uint256 amount = 1 ether;
        bytes memory extra = hex"dead";

        bytes memory message = abi.encodeWithSelector(
            bridge.finalizeBridgeETH.selector,
            alice,
            bob,
            amount,
            extra
        );

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHWithdrawalFinalized(alice, bob, amount, extra);

        vm.expectEmit(true, true, true, true, address(bridge));
        emit ETHBridgeFinalized(alice, bob, amount, extra);

        (bool ok, ) = _relayFromOtherBridge(fakeL2Bridge, address(bridge), amount, message);
        assertTrue(ok);
    }

    function _deployPortal() internal returns (ComposePortal portal_) {
        ComposePortal impl = new ComposePortal(PROOF_MATURITY_DELAY);
        Proxy proxy = new Proxy(address(composeProxyAdmin));

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgrade(payable(address(proxy)), address(impl));

        portal_ = ComposePortal(payable(address(proxy)));

        stdstore
            .target(address(portal_))
            .sig(portal_.ethLockbox.selector)
            .checked_write(address(composeETHLockbox));

        vm.prank(proxyAdminOwner);
        portal_.initialize(ISystemConfig(address(systemConfig)), IAnchorStateRegistry(address(asr)));
    }

    function _deployErc20Lockbox(ComposePortal portal_) internal returns (ComposeERC20Lockbox lb_) {
        ComposeERC20Lockbox impl = new ComposeERC20Lockbox();
        Proxy proxy = new Proxy(address(composeProxyAdmin));

        IComposePortal[] memory portals = new IComposePortal[](1);
        portals[0] = IComposePortal(address(portal_));

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy)),
            address(impl),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, portals))
        );
        lb_ = ComposeERC20Lockbox(address(proxy));

        vm.prank(proxyAdminOwner);
        portal_.initializeCompose(IComposeERC20Lockbox(address(lb_)));
    }

    function _deployBridge(ComposePortal portal_, ComposeERC20Lockbox lb_) internal returns (ComposeL1Bridge b_) {
        ComposeL1Bridge impl = new ComposeL1Bridge();
        Proxy proxy = new Proxy(address(composeProxyAdmin));

        bytes memory initData = abi.encodeCall(
            ComposeL1Bridge.initialize,
            (
                ICrossDomainMessenger(address(messenger)),
                address(0),
                composeSuperchainConfig,
                IComposeERC20Lockbox(address(lb_)),
                IComposePortalERC20(address(portal_))
            )
        );

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(payable(address(proxy)), address(impl), initData);

        b_ = ComposeL1Bridge(payable(address(proxy)));
    }

    function _enterFinalize(address l2Sender) internal {
        stdstore
            .target(address(portal))
            .sig(portal.l2Sender.selector)
            .checked_write(l2Sender);
    }

    function _exitFinalize() internal {
        stdstore
            .target(address(portal))
            .sig(portal.l2Sender.selector)
            .checked_write(Constants.DEFAULT_L2_SENDER);
    }

    function _relayFromOtherBridge(
        address otherBridge,
        address target,
        uint256 value,
        bytes memory message
    )
        internal
        returns (bool ok, bytes memory ret)
    {
        (ok, ret) = messenger.relayFromOtherBridge{ value: value }(otherBridge, target, value, message);
    }

    function test_setup_wiring() public view {
        assertTrue(address(portal) != address(0));
        assertTrue(address(bridge) != address(0));
        assertTrue(address(erc20Lockbox) != address(0));

        assertEq(address(portal.erc20Lockbox()), address(erc20Lockbox));
        assertEq(address(portal.ethLockbox()), address(composeETHLockbox));
        assertTrue(portal.authorizedBridges(address(bridge)));
        assertEq(portal.l2Sender(), Constants.DEFAULT_L2_SENDER);

        assertTrue(erc20Lockbox.authorizedPortals(IComposePortal(address(portal))));
        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal2(payable(address(portal)))));

        assertEq(address(bridge.messenger()), address(messenger));
        assertEq(address(bridge.erc20Lockbox()), address(erc20Lockbox));
        assertEq(address(bridge.composePortal()), address(portal));
        assertEq(address(bridge.superchainConfig()), address(composeSuperchainConfig));
        assertEq(bridge.otherBridge(), address(0));
    }

    function test_setup_portalVersion() public {
        assertEq(portal.version(), "1.0.0-compose");
    }

    function test_setup_portalErc20LockboxSet() public {
        assertEq(address(portal.erc20Lockbox()), address(erc20Lockbox));
    }

    function test_setup_portalEthLockboxSet() public {
        assertEq(address(portal.ethLockbox()), address(composeETHLockbox));
    }

    function test_setup_portalAuthorizedBridgeMapping() public {
        assertTrue(portal.authorizedBridges(address(bridge)));
    }

    function test_setup_erc20LockboxAuthorizedPortal() public {
        assertTrue(erc20Lockbox.authorizedPortals(IComposePortal(address(portal))));
    }

    function test_setup_ethLockboxAuthorizedPortal() public {
        assertTrue(composeETHLockbox.authorizedPortals(IOptimismPortal2(payable(address(portal)))));
    }
}
