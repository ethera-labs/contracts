// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { ComposeCommonTest } from "test/setup/ComposeCommonTest.sol";
import { ComposeL1StandardBridge } from "src/ComposeL1StandardBridge.sol";
import { ComposeERC20Lockbox } from "src/ComposeERC20Lockbox.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";
import { ISuperchainConfig } from "@optimism/interfaces/L1/ISuperchainConfig.sol";
import { ICrossDomainMessenger } from "@optimism/interfaces/universal/ICrossDomainMessenger.sol";
import { ISystemConfig } from "@optimism/interfaces/L1/ISystemConfig.sol";
import { L1StandardBridge } from "@optimism/src/L1/L1StandardBridge.sol";
import { StandardBridge } from "@optimism/src/universal/StandardBridge.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOptimismMintableERC20 } from "@optimism/interfaces/universal/IOptimismMintableERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MockERC20ForBridge is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockOptimismMintableERC20 is ERC20 {
    address public remoteToken;
    address public bridge;

    constructor(address _bridge, address _remoteToken) ERC20("Mintable", "MINT") {
        bridge = _bridge;
        remoteToken = _remoteToken;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == bridge, "only bridge");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == bridge, "only bridge");
        _burn(from, amount);
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IOptimismMintableERC20).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}

contract MockMessenger {
    address public xDomainMessageSenderValue;
    address public lastTarget;
    bytes public lastMessage;
    uint32 public lastMinGasLimit;

    function setXDomainMessageSender(address _sender) external {
        xDomainMessageSenderValue = _sender;
    }

    function xDomainMessageSender() external view returns (address) {
        return xDomainMessageSenderValue;
    }

    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable {
        lastTarget = _target;
        lastMessage = _message;
        lastMinGasLimit = _minGasLimit;
    }
}

contract MockSystemConfig {
    bool internal _paused;
    ISuperchainConfig internal _superchainConfig;

    function setPaused(bool paused_) external {
        _paused = paused_;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function setSuperchainConfig(ISuperchainConfig sc) external {
        _superchainConfig = sc;
    }

    function superchainConfig() external view returns (ISuperchainConfig) {
        return _superchainConfig;
    }
}

contract ComposeL1StandardBridgeTest is ComposeCommonTest {
    ComposeL1StandardBridge internal bridge;
    ComposeERC20Lockbox internal erc20Lockbox;
    MockMessenger internal mockMessenger;
    MockSystemConfig internal mockSystemConfig;
    MockERC20ForBridge internal token;
    address internal remoteToken;
    address internal l2Bridge;

    function setUp() public override {
        super.setUp();

        remoteToken = makeAddr("remoteToken");
        l2Bridge = 0x4200000000000000000000000000000000000010;

        mockMessenger = new MockMessenger();
        mockSystemConfig = new MockSystemConfig();
        mockSystemConfig.setSuperchainConfig(composeSuperchainConfig);

        ComposeL1StandardBridge bridgeImpl = new ComposeL1StandardBridge();
        Proxy bridgeProxy = new Proxy(address(composeProxyAdmin));

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(bridgeProxy)),
            address(bridgeImpl),
            abi.encodeCall(
                L1StandardBridge.initialize,
                (ICrossDomainMessenger(address(mockMessenger)), ISystemConfig(address(mockSystemConfig)))
            )
        );

        bridge = ComposeL1StandardBridge(payable(address(bridgeProxy)));

        ComposeERC20Lockbox lockboxImpl = new ComposeERC20Lockbox();
        Proxy lockboxProxy = new Proxy(address(composeProxyAdmin));

        address[] memory bridges = new address[](1);
        bridges[0] = address(bridge);

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(lockboxProxy)),
            address(lockboxImpl),
            abi.encodeCall(ComposeERC20Lockbox.initialize, (composeSuperchainConfig, bridges))
        );

        erc20Lockbox = ComposeERC20Lockbox(address(lockboxProxy));

        vm.prank(proxyAdminOwner);
        bridge.setERC20Lockbox(IComposeERC20Lockbox(address(erc20Lockbox)));

        token = new MockERC20ForBridge("Test Token", "TT");
    }

    function _simulateFinalize(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
    {
        mockMessenger.setXDomainMessageSender(l2Bridge);
        vm.prank(address(mockMessenger));
        bridge.finalizeBridgeERC20(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    function test_bridgeERC20_locksInLockbox() public {
        uint256 amount = 1000e18;
        token.mint(alice, amount);

        vm.prank(alice);
        token.approve(address(erc20Lockbox), amount);

        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, amount, 200_000, hex"");

        assertEq(token.balanceOf(address(erc20Lockbox)), amount);
        assertEq(token.balanceOf(address(bridge)), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_bridgeERC20_tracksTotalDepositedInLockbox() public {
        uint256 amount = 500e18;
        token.mint(alice, amount);

        vm.prank(alice);
        token.approve(address(erc20Lockbox), amount);

        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, amount, 200_000, hex"");

        assertEq(erc20Lockbox.totalDeposited(address(token)), amount);
        assertEq(bridge.deposits(address(token), remoteToken), 0);
    }

    function test_bridgeERC20_sendsMessageToMessenger() public {
        uint256 amount = 100e18;
        token.mint(alice, amount);

        vm.prank(alice);
        token.approve(address(erc20Lockbox), amount);

        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, amount, 200_000, hex"");

        assertEq(mockMessenger.lastTarget(), l2Bridge);
        assertEq(mockMessenger.lastMinGasLimit(), 200_000);
    }

    function test_bridgeERC20To_locksInLockbox() public {
        uint256 amount = 1000e18;
        token.mint(alice, amount);

        vm.prank(alice);
        token.approve(address(erc20Lockbox), amount);

        vm.prank(alice);
        bridge.bridgeERC20To(address(token), remoteToken, bob, amount, 200_000, hex"");

        assertEq(token.balanceOf(address(erc20Lockbox)), amount);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_finalizeBridgeERC20_unlocksFromLockbox() public {
        uint256 lockAmount = 1000e18;
        uint256 unlockAmount = 400e18;

        token.mint(alice, lockAmount);
        vm.prank(alice);
        token.approve(address(erc20Lockbox), lockAmount);
        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, lockAmount, 200_000, hex"");

        _simulateFinalize(address(token), remoteToken, alice, bob, unlockAmount, hex"");

        assertEq(token.balanceOf(bob), unlockAmount);
        assertEq(token.balanceOf(address(erc20Lockbox)), lockAmount - unlockAmount);
        assertEq(erc20Lockbox.totalDeposited(address(token)), lockAmount - unlockAmount);
    }

    function test_finalizeBridgeERC20_revertsIfNotFromMessenger() public {
        vm.prank(alice);
        vm.expectRevert("StandardBridge: function can only be called from the other bridge");
        bridge.finalizeBridgeERC20(address(token), remoteToken, alice, bob, 100e18, hex"");
    }

    function test_finalizeBridgeERC20_revertsIfWrongXDomainSender() public {
        mockMessenger.setXDomainMessageSender(alice);
        vm.prank(address(mockMessenger));
        vm.expectRevert("StandardBridge: function can only be called from the other bridge");
        bridge.finalizeBridgeERC20(address(token), remoteToken, alice, bob, 100e18, hex"");
    }

    function test_finalizeBridgeERC20_revertsWhenBridgePaused() public {
        uint256 amount = 1000e18;
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(erc20Lockbox), amount);
        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, amount, 200_000, hex"");

        mockSystemConfig.setPaused(true);

        mockMessenger.setXDomainMessageSender(l2Bridge);
        vm.prank(address(mockMessenger));
        vm.expectRevert(ComposeL1StandardBridge.ComposeBridge_Paused.selector);
        bridge.finalizeBridgeERC20(address(token), remoteToken, alice, bob, 500e18, hex"");
    }

    function test_mintableToken_burnOnBridge() public {
        MockOptimismMintableERC20 mintable = new MockOptimismMintableERC20(address(bridge), remoteToken);
        uint256 amount = 500e18;

        vm.prank(address(bridge));
        mintable.mint(alice, amount);

        vm.prank(alice);
        mintable.approve(address(bridge), amount);

        vm.prank(alice, alice);
        bridge.bridgeERC20(address(mintable), remoteToken, amount, 200_000, hex"");

        assertEq(mintable.totalSupply(), 0);
        assertEq(token.balanceOf(address(erc20Lockbox)), 0);
    }

    function test_mintableToken_mintOnFinalize() public {
        MockOptimismMintableERC20 mintable = new MockOptimismMintableERC20(address(bridge), remoteToken);
        uint256 amount = 500e18;

        _simulateFinalize(address(mintable), remoteToken, alice, bob, amount, hex"");

        assertEq(mintable.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(erc20Lockbox)), 0);
    }

    function test_mintableToken_revertsOnWrongRemoteToken() public {
        address wrongRemote = makeAddr("wrongRemote");
        MockOptimismMintableERC20 mintable = new MockOptimismMintableERC20(address(bridge), remoteToken);

        vm.prank(address(bridge));
        mintable.mint(alice, 100e18);
        vm.prank(alice);
        mintable.approve(address(bridge), 100e18);

        vm.prank(alice, alice);
        vm.expectRevert(ComposeL1StandardBridge.ComposeBridge_WrongRemoteToken.selector);
        bridge.bridgeERC20(address(mintable), wrongRemote, 100e18, 200_000, hex"");
    }

    function test_mintableToken_finalizeRevertsOnWrongRemoteToken() public {
        address wrongRemote = makeAddr("wrongRemote");
        MockOptimismMintableERC20 mintable = new MockOptimismMintableERC20(address(bridge), remoteToken);

        mockMessenger.setXDomainMessageSender(l2Bridge);
        vm.prank(address(mockMessenger));
        vm.expectRevert(ComposeL1StandardBridge.ComposeBridge_WrongRemoteToken.selector);
        bridge.finalizeBridgeERC20(address(mintable), wrongRemote, alice, bob, 100e18, hex"");
    }

    function test_crossRollup_depositViaBridge1_withdrawViaBridge2() public {
        ComposeL1StandardBridge bridge2 = _deploySecondBridge();

        uint256 depositAmount = 2000e18;
        token.mint(alice, depositAmount);
        vm.prank(alice);
        token.approve(address(erc20Lockbox), depositAmount);
        vm.prank(alice, alice);
        bridge.bridgeERC20(address(token), remoteToken, depositAmount, 200_000, hex"");

        assertEq(token.balanceOf(address(erc20Lockbox)), depositAmount);

        MockMessenger mockMessenger2 = MockMessenger(address(bridge2.messenger()));
        uint256 withdrawAmount = 800e18;
        mockMessenger2.setXDomainMessageSender(l2Bridge);
        vm.prank(address(mockMessenger2));
        bridge2.finalizeBridgeERC20(address(token), remoteToken, alice, bob, withdrawAmount, hex"");

        assertEq(token.balanceOf(bob), withdrawAmount);
        assertEq(token.balanceOf(address(erc20Lockbox)), depositAmount - withdrawAmount);
        assertEq(erc20Lockbox.totalDeposited(address(token)), depositAmount - withdrawAmount);
    }

    function test_setERC20Lockbox_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.setERC20Lockbox(IComposeERC20Lockbox(address(0)));
    }

    function test_setERC20Lockbox_success() public {
        address newLockbox = makeAddr("newLockbox");
        vm.prank(proxyAdminOwner);
        bridge.setERC20Lockbox(IComposeERC20Lockbox(newLockbox));

        assertEq(address(bridge.erc20Lockbox()), newLockbox);
    }

    function _deploySecondBridge() internal returns (ComposeL1StandardBridge) {
        MockMessenger messenger2 = new MockMessenger();
        MockSystemConfig systemConfig2 = new MockSystemConfig();
        systemConfig2.setSuperchainConfig(composeSuperchainConfig);

        ComposeL1StandardBridge impl2 = new ComposeL1StandardBridge();
        Proxy proxy2 = new Proxy(address(composeProxyAdmin));

        vm.prank(proxyAdminOwner);
        composeProxyAdmin.upgradeAndCall(
            payable(address(proxy2)),
            address(impl2),
            abi.encodeCall(
                L1StandardBridge.initialize,
                (ICrossDomainMessenger(address(messenger2)), ISystemConfig(address(systemConfig2)))
            )
        );

        ComposeL1StandardBridge bridge2 = ComposeL1StandardBridge(payable(address(proxy2)));

        vm.prank(proxyAdminOwner);
        erc20Lockbox.authorizeBridge(address(bridge2));

        vm.prank(proxyAdminOwner);
        bridge2.setERC20Lockbox(IComposeERC20Lockbox(address(erc20Lockbox)));

        return bridge2;
    }
}
