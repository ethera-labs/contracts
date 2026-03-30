// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Setup } from "@ssv/test/Setup.t.sol";
import { UniversalBridge } from "@ssv/src/bridge/UniversalBridge.sol";
import { UniversalBridgeMailbox } from "@ssv/src/bridge/UniversalBridgeMailbox.sol";
import { CetFactory } from "@ssv/src/bridge/CetFactory.sol";
import { ComposableERC20 } from "@ssv/src/bridge/ComposableErc20.sol";
import { IUniversalBridgeMailbox } from "@ssv/src/bridge/interfaces/IUniversalBridgeMailbox.sol";
import { IUniversalBridge } from "@ssv/src/bridge/interfaces/IUniversalBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockETHLiquidity {
    event LiquidityBurned(address indexed caller, uint256 value);
    event LiquidityMinted(address indexed caller, uint256 value);

    function burn() external payable {
        emit LiquidityBurned(msg.sender, msg.value);
    }

    function mint(uint256 _amount) external {
        (bool ok,) = msg.sender.call{value: _amount}("");
        require(ok, "mint transfer failed");
        emit LiquidityMinted(msg.sender, _amount);
    }

    receive() external payable {}
}

contract UniversalBridgeTest is Setup {
    UniversalBridge internal bridgeU;
    UniversalBridgeMailbox internal bridgeMailbox;
    CetFactory internal cetFactory;
    MockETHLiquidity internal ethLiquidity;

    address internal l1Asset = address(0xAAAA);
    address internal tokenSrc;
    address internal receiver;
    uint256 internal amount = 1000;
    uint256 internal sessionId = 12345;

    string internal name = "TestToken";
    string internal symbol = "TT";
    uint8 internal decimals = 18;
    uint256 internal originChainId = 1;

    function setUp() public override {
        super.setUp();

        bridgeMailbox = new UniversalBridgeMailbox(COORDINATOR);
        cetFactory = new CetFactory();
        ethLiquidity = new MockETHLiquidity();
        bridgeU = new UniversalBridge(address(bridgeMailbox), address(cetFactory), address(ethLiquidity));
        bridgeMailbox.setBridge(address(bridgeU));
        cetFactory.setBridge(address(bridgeU));

        tokenSrc = address(
            new ComposableERC20(
                l1Asset,
                block.chainid,
                name,
                symbol,
                decimals,
                address(bridgeU)
            )
        );

        receiver = COORDINATOR;
    }

    function _putAckForCheck(
        uint256 sessionId_,
        uint256 ackChainSrc,
        address ackSender,
        address ackReceiver,
        address token,
        uint256 ackAmount
    ) internal {
        vm.prank(COORDINATOR);
        bridgeMailbox.putInbox(
            ackChainSrc,
            ackSender,
            ackReceiver,
            sessionId_,
            "ACK",
            abi.encode(token, ackAmount)
        );
    }

    function _putSend(
        uint256 chainSrc,
        address sender,
        address receiverForMailbox,
        uint256 sessionId_,
        bytes memory payload
    ) internal {
        vm.prank(COORDINATOR);
        bridgeMailbox.putInbox(
            chainSrc,
            sender,
            receiverForMailbox,
            sessionId_,
            "SEND_TOKENS",
            payload
        );
    }

    function testBridgeERC20To_LocksAndWrites() public {
        MockERC20 plainToken = new MockERC20("Plain", "PLN");
        plainToken.mint(DEPLOYER, amount);

        _putAckForCheck(sessionId, 2, receiver, address(bridgeU), address(plainToken), amount);

        vm.startPrank(DEPLOYER);
        IERC20(address(plainToken)).approve(address(bridgeU), amount);

        vm.expectEmit(true, true, true, true);
        emit IUniversalBridge.TokensLocked(address(plainToken), DEPLOYER, amount);

        vm.expectEmit(true, true, true, true);
        emit IUniversalBridge.MailboxWrite(2, receiver, sessionId, "SEND_TOKENS");

        bridgeU.bridgeERC20To(2, address(plainToken), amount, receiver, sessionId);
        vm.stopPrank();
    }

    function testBridgeCETTo_BurnsAndWrites() public {
        vm.prank(address(bridgeU));
        address cetAddr = cetFactory.deployIfAbsent(
            l1Asset,
            originChainId,
            decimals,
            name,
            symbol
        );

        _putAckForCheck(sessionId, 2, receiver, address(bridgeU), l1Asset, amount);

        vm.startPrank(address(bridgeU));
        ComposableERC20(cetAddr).crosschainMint(DEPLOYER, amount);
        vm.stopPrank();

        vm.startPrank(DEPLOYER);
        bridgeU.bridgeCETTo(2, cetAddr, amount, receiver, sessionId);
        vm.stopPrank();

        assertEq(ComposableERC20(cetAddr).balanceOf(DEPLOYER), 0);
    }

    function testReceiveTokens_MintsCETWhenNeeded() public {
        bytes memory payload = abi.encode(originChainId, l1Asset, amount, name, symbol, decimals);

        _putSend(originChainId, address(bridgeU), receiver, sessionId, payload);

        IUniversalBridgeMailbox.MessageHeader memory header = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: originChainId,
            chainDest: block.chainid,
            sender: address(bridgeU),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_TOKENS"
        });

        vm.startPrank(receiver);
        (address token, uint256 amt) = bridgeU.receiveTokens(header);
        vm.stopPrank();

        assertEq(amt, amount, "amount mismatch");
        assertGt(token.code.length, 0, "CET must exist");
        assertEq(IERC20(token).balanceOf(receiver), amount, "not minted to receiver");
    }

    function testReceiveTokens_RevertsWhenWrongCaller() public {
        IUniversalBridgeMailbox.MessageHeader memory header = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: originChainId,
            chainDest: block.chainid,
            sender: address(bridgeU),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_TOKENS"
        });

        vm.startPrank(address(0xBAD));
        vm.expectRevert(IUniversalBridge.NotReceiver.selector);
        bridgeU.receiveTokens(header);
        vm.stopPrank();
    }

    function testReceiveTokens_RevertsOnMissingMessage() public {
        IUniversalBridgeMailbox.MessageHeader memory header = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: originChainId,
            chainDest: block.chainid,
            sender: address(bridgeU),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_TOKENS"
        });

        vm.startPrank(receiver);
        vm.expectRevert(IUniversalBridgeMailbox.MessageNotFound.selector);
        bridgeU.receiveTokens(header);
        vm.stopPrank();
    }

    function testBridgeEthTo_BurnsAndWrites() public {
        uint256 ethAmount = 1 ether;
        _putAckForCheck(sessionId, 2, receiver, address(bridgeU), address(0), ethAmount);

        vm.deal(DEPLOYER, ethAmount);
        vm.startPrank(DEPLOYER);

        vm.expectEmit(true, true, true, true);
        emit IUniversalBridge.ETHLocked(DEPLOYER, ethAmount);

        vm.expectEmit(true, true, true, true);
        emit IUniversalBridge.MailboxWrite(2, receiver, sessionId, "SEND_ETH");

        bridgeU.bridgeEthTo{value: ethAmount}(sessionId, 2, receiver);
        vm.stopPrank();

        assertEq(DEPLOYER.balance, 0, "ETH should be transferred from sender");
    }

    function testBridgeEthTo_RevertsWithNoValue() public {
        vm.startPrank(DEPLOYER);
        vm.expectRevert(IUniversalBridge.NoETHSent.selector);
        bridgeU.bridgeEthTo{value: 0}(sessionId, 2, receiver);
        vm.stopPrank();
    }

    function testReceiveETH_MintsAndTransfers() public {
        uint256 ethAmount = 1 ether;

        // Fund the ETHLiquidity mock so it can mint
        vm.deal(address(ethLiquidity), ethAmount);

        bytes memory payload = abi.encode(originChainId, ethAmount);

        // Put SEND_ETH message into mailbox
        vm.prank(COORDINATOR);
        bridgeMailbox.putInbox(
            originChainId,
            address(bridgeU),
            receiver,
            sessionId,
            "SEND_ETH",
            payload
        );

        IUniversalBridgeMailbox.MessageHeader memory header = IUniversalBridgeMailbox.MessageHeader({
            chainSrc: originChainId,
            chainDest: block.chainid,
            sender: address(bridgeU),
            receiver: receiver,
            sessionId: sessionId,
            label: "SEND_ETH"
        });

        uint256 balBefore = receiver.balance;
        vm.startPrank(receiver);
        uint256 amt = bridgeU.receiveETH(header);
        vm.stopPrank();

        assertEq(amt, ethAmount, "amount mismatch");
        assertEq(receiver.balance - balBefore, ethAmount, "ETH not transferred to receiver");
    }

    function testRedeemWrappedCET() public {
        // Deploy a "CoreComposeable": remoteAsset = itself, remoteChainID = block.chainid
        // We use a trick: deploy a ComposableERC20 where remoteAsset will be set to l1Asset first,
        // then we need the core to point to itself. Instead, let's use the factory to create a wrapped
        // and a separate token as "core".

        // Core CET: remoteAsset = its own address, remoteChainID = block.chainid
        // We'll deploy it manually with remoteAsset = address we predict
        // Simpler: deploy wrappedCET with remoteAsset pointing to a coreCET

        // Deploy coreCET as a real CoreComposeable: remoteAsset = its own address, remoteChainID = block.chainid
        // Predict the CREATE address so we can pass it as remoteAsset in the constructor
        uint256 nonce = vm.getNonce(address(this));
        address predictedCoreCET = vm.computeCreateAddress(address(this), nonce);

        address coreCET = address(
            new ComposableERC20(
                predictedCoreCET,
                block.chainid,
                "CoreToken",
                "CORE",
                18,
                address(bridgeU)
            )
        );
        assert(coreCET == predictedCoreCET);

        address wrappedCET = address(
            new ComposableERC20(
                coreCET, // remoteAsset points to coreCET
                originChainId,
                "WrappedToken",
                "WRAP",
                18,
                address(bridgeU)
            )
        );

        // Mint wrapped tokens to DEPLOYER
        vm.startPrank(address(bridgeU));
        ComposableERC20(wrappedCET).crosschainMint(DEPLOYER, amount);
        vm.stopPrank();

        // Redeem
        vm.startPrank(DEPLOYER);

        vm.expectEmit(true, true, true, true);
        emit IUniversalBridge.WrappedCETRedeemed(wrappedCET, coreCET, DEPLOYER, amount);

        bridgeU.redeemWrappedCET(wrappedCET, coreCET, amount);
        vm.stopPrank();

        assertEq(ComposableERC20(wrappedCET).balanceOf(DEPLOYER), 0, "wrapped not burned");
        assertEq(ComposableERC20(coreCET).balanceOf(DEPLOYER), amount, "core not minted");
    }

    function testRedeemWrappedCET_RevertsOnNotCoreComposeable() public {
        // Deploy a non-core CET (remoteAsset != itself) to use as coreCET
        address notCoreCET = address(
            new ComposableERC20(
                l1Asset, // remoteAsset != notCoreCET, so isCoreComposeable returns false
                originChainId,
                "NotCore",
                "NC",
                18,
                address(bridgeU)
            )
        );

        address fakeCET = address(
            new ComposableERC20(
                notCoreCET, // remoteAsset points to notCoreCET
                originChainId,
                "FakeToken",
                "FAKE",
                18,
                address(bridgeU)
            )
        );

        vm.startPrank(DEPLOYER);
        vm.expectRevert(IUniversalBridge.NotCoreComposeable.selector);
        bridgeU.redeemWrappedCET(fakeCET, notCoreCET, amount);
        vm.stopPrank();
    }

    function testCheckAck_RevertsWithoutAck() public {
        MockERC20 plainToken = new MockERC20("Plain", "PLN");
        plainToken.mint(DEPLOYER, amount);

        vm.startPrank(DEPLOYER);
        IERC20(address(plainToken)).approve(address(bridgeU), amount);
        vm.expectRevert(IUniversalBridgeMailbox.MessageNotFound.selector);
        bridgeU.bridgeERC20To(2, address(plainToken), amount, receiver, sessionId);
        vm.stopPrank();
    }
}