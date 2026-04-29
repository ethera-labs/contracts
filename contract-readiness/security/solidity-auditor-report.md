# Security Review — ethera-contracts

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | default (continued from `/tmp/audit-CUD6T0/`)          |
| **Files reviewed**               | `ComposeAnchorStateRegistry.sol` · `ComposeDisputeGame.sol` · `ComposeERC20Lockbox.sol`<br>`ComposeETHLockbox.sol` · `ComposeL1Bridge.sol` · `ComposePortal.sol`<br>`CETFactory.sol` · `ComposableERC20.sol` · `ComposeETHLiquidity.sol`<br>`ComposeL2ToL2Bridge.sol` · `L2ComposeBridge.sol` · `UniversalBridgeMailbox.sol`<br>`Bridge.sol` · `BridgeableToken.sol` · `Mailbox.sol`<br>`PingPong.sol` · `SSVMintable.sol` · `USDCMintable.sol`<br>`USDC_SSV_WETH_Swapper.sol` · 23 deployment/script files<br>_Note: `ComposeL2OutputOracle.sol` is deprecated and excluded from this review._ |
| **Confidence threshold (1-100)** | 80                                                     |

> Continuation note: this report folds in the 12 deep-validated findings from `scv-scan.md`, applies the four-gate judging from `solidity-auditor/judging.md`, and adds findings from the Agents 2–8 perspectives (math/precision, access-control, economic-security, execution-trace, invariant, periphery, first-principles). Two prior High findings are downgraded after refutation; several new High/Medium issues are added.

---

## Findings

[95] **1. `BridgeableToken.burn` / `mint` unrestricted — anyone can mint or burn arbitrary balances**

`BridgeableToken.burn` · `BridgeableToken.mint` · Confidence: 95

**Description**
Both functions are `public` with no caller check despite the contract storing a `BRIDGE` immutable, so any account can mint or burn tokens at will and the token has no integrity guarantee.

**Fix**

```diff
 function burn(address account, uint256 value) public {
+    require(msg.sender == BRIDGE, "BridgeableToken: only bridge");
     _burn(account, value);
 }
 function mint(address account, uint256 value) public {
+    require(msg.sender == BRIDGE, "BridgeableToken: only bridge");
     _mint(account, value);
 }
```
---

[95] **2. `USDC_SSV_WETH_Swapper.withdrawTokens` unrestricted — anyone can drain liquidity**

`USDC_SSV_WETH_Swapper.withdrawTokens` · Confidence: 95

**Description**
`withdrawTokens(token, amount)` transfers any amount of any token to `msg.sender` with zero access control, letting any user empty the swapper in one call.

**Fix**

```diff
+address public immutable owner;
+constructor(address _weth, address _usdc, address _ssv) {
+    owner = msg.sender; ...
+}
 function withdrawTokens(address token, uint256 amount) external {
+    require(msg.sender == owner, "not owner");
     IERC20(token).transfer(msg.sender, amount);
 }
```
---

[90] **3. `SSVMintable` / `USDCMintable` unrestricted `mint`/`burn`**

`SSVMintable.mint` · `SSVMintable.burn` · `USDCMintable.mint` · `USDCMintable.burn` · Confidence: 90

**Description**
Both DEX tokens expose `public mint`/`burn` with no access control; combined with `USDC_SSV_WETH_Swapper`, an attacker can mint input tokens to manipulate `_getAmountOut` and drain the output reserve.

**Fix**

```diff
+address public immutable minter;
 function mint(address account, uint256 value) public {
+    require(msg.sender == minter, "only minter");
     _mint(account, value);
 }
```
---

[90] **4. `ComposeL2ToL2Bridge.bridgeERC20To` / `bridgeCETTo` always revert — outbound L2↔L2 bridge is non-functional**

`ComposeL2ToL2Bridge.bridgeERC20To` · `ComposeL2ToL2Bridge.bridgeCETTo` · Confidence: 90

**Description**
Both functions call `checkAck(...)` in the same transaction immediately after `mailbox.writeMessage(...)`. The ACK is written by `receiveTokens` on the destination chain after coordinator delivery, so on the first send the inbox key does not exist yet and `checkAck` reverts with `NoAckMessage` — every outbound ERC20/CET send fails. (Severity raised from Low: this is a complete denial of service, not a bug-class hint.)

**Fix**

```diff
- mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: sendHeader, payload: payload}));
- checkAck(sessionId, chainDest, receiver, address(this), tokenSrc, amount);
+ mailbox.writeMessage(IUniversalBridgeMailbox.Message({header: sendHeader, payload: payload}));
+ // checkAck must be a separate user-initiated step after the destination chain
+ // delivers the ACK via the coordinator.
```

Add a separate `claimAck(sessionId, chainDest, receiver, tokenSrc, amount)` function that performs the existing `checkAck` validation and unlocks any escrow that should follow the ACK.

---

[88] **5. `CetFactory` retains revoked bridges in `bridgeList` and re-authorizes them on every new CET**

`CetFactory.revokeBridge` · `CetFactory._authorizeAllBridges` · Confidence: 88

**Description**
`revokeBridge` clears `authorizedBridges[_bridge]` but never removes the entry from `bridgeList`. `_authorizeAllBridges`, called from `deployIfAbsent`, iterates `bridgeList` and re-grants authorization on every newly deployed CET — so a bridge revoked because it was compromised is silently re-authorized for every future token, defeating the revoke entirely.

**Fix**

```diff
 function revokeBridge(address _bridge) external {
     if (msg.sender != deployer) revert OnlyDeployer();
     authorizedBridges[_bridge] = false;
+    for (uint256 i; i < bridgeList.length; i++) {
+        if (bridgeList[i] == _bridge) {
+            bridgeList[i] = bridgeList[bridgeList.length - 1];
+            bridgeList.pop();
+            break;
+        }
+    }
     emit BridgeRevoked(_bridge);
 }
```

Or filter `_authorizeAllBridges` on `authorizedBridges[bridgeList[i]]` before granting.

---

[85] **6. `ComposeERC20Lockbox.migrateLiquidity` moves tokens but not accounting — destination cannot unlock**

`ComposeERC20Lockbox.migrateLiquidity` · `ComposeERC20Lockbox.receiveLiquidity` · Confidence: 85

**Description**
`migrateLiquidity` `safeTransfer`s the full token balance to the receiving lockbox and emits an event, but never decrements `totalDeposited[_token]` on the source nor increments it on the destination (`receiveLiquidity` only emits). Post-migration, `unlockERC20` on the destination reverts at `if (totalDeposited[_token] < _amount)`, so the migrated funds are stranded; on the source, `totalDeposited` exceeds `balanceOf(this)`, breaking the deposit invariant for any subsequent `lockERC20`.

**Fix**

```diff
 function migrateLiquidity(address _token, IComposeERC20Lockbox _lockbox) external {
     _assertOnlyProxyAdminOwner();
     uint256 bal = IERC20(_token).balanceOf(address(this));
+    uint256 deposited = totalDeposited[_token];
+    totalDeposited[_token] = 0;
     IERC20(_token).safeTransfer(address(_lockbox), bal);
-    _lockbox.receiveLiquidity(_token, bal);
+    _lockbox.receiveLiquidity(_token, deposited);
     emit LiquidityMigrated(_token, _lockbox, bal);
 }
 function receiveLiquidity(address _token, uint256 _amount) external {
     IComposeERC20Lockbox senderLb = IComposeERC20Lockbox(msg.sender);
     if (!authorizedLockboxes[senderLb]) revert ERC20Lockbox_Unauthorized();
+    totalDeposited[_token] += _amount;
     emit LiquidityReceived(_token, senderLb, _amount);
 }
```
---

[82] **7. Fee-on-transfer / rebasing tokens break `ComposeERC20Lockbox.lockERC20` accounting**

`ComposeERC20Lockbox.lockERC20` · Confidence: 82

**Description**
`lockERC20` increments `totalDeposited[_token] += _amount` using the caller-supplied amount, then asserts `balanceOf(this) >= totalDeposited[_token]`. For fee-on-transfer or rebasing tokens, only `_amount - fee` actually arrives, so either the assertion reverts on legitimate deposits or, if the assertion happens to pass once per-token accounting is offset, `totalDeposited` permanently overstates lockbox holdings and the last withdrawer cannot exit.

**Fix**

```diff
+ uint256 balBefore = IERC20(_token).balanceOf(address(this));
+ // portal must already have transferred tokens before calling
+ uint256 received = balBefore - (totalDeposited[_token]); // i.e. delta vs prior
+ totalDeposited[_token] += received;
- totalDeposited[_token] += _amount;
- if (IERC20(_token).balanceOf(address(this)) < totalDeposited[_token]) revert ...;
```

Or whitelist supported tokens and explicitly document FoT/rebasing as unsupported.

---

[82] **8. `L2ComposeBridge.onlyEOA` blocks smart-account/AA users (and is fully bypassable from constructors)**

`L2ComposeBridge.onlyEOA` · Confidence: 82

**Description**
The modifier reverts on `msg.sender != tx.origin`; this both excludes every legitimate ERC-4337 / multisig / smart-wallet user from the most common bridge entry points and is bypassable by attacker contracts in their constructor (where `extcodesize` is 0). Either remove the check (canonical OP L2 bridges do not enforce this) or replace with a documented allowlist.

**Fix**

```diff
- modifier onlyEOA() {
-     if (msg.sender != tx.origin) revert NotEOA();
-     _;
- }
+ // Drop the modifier entirely, or replace with an explicit allowlist of trusted
+ // contract callers (multisigs, etc.) if accidental contract-wallet deposits are
+ // a concern.
```
---

[82] **9. `CetFactory._authorizeAllBridges` unbounded loop — DoS on every new CET deployment**

`CetFactory._authorizeAllBridges` · `CetFactory.deployIfAbsent` · Confidence: 82

**Description**
`_authorizeAllBridges` iterates `bridgeList` to grant permissions on every newly deployed CET. The list has no upper bound, and `deployIfAbsent` is in the hot path of every cross-chain ERC20 receive on L2; once `bridgeList` is large enough, `deployIfAbsent` runs out of gas and no new CET can ever be deployed.

**Fix**

```diff
+ uint256 internal constant MAX_BRIDGES = 32;
 function authorizeBridge(address _bridge) external {
     if (msg.sender != deployer) revert OnlyDeployer();
     if (_bridge == address(0)) revert ZeroAddress();
+    require(bridgeList.length < MAX_BRIDGES, "too many bridges");
     ...
 }
```

Or have each `ComposableERC20` query the factory at mint/burn time instead of replicating per-token.

---

[80] **10. `UniversalBridgeMailbox.readMessage` lets any authorized bridge consume any other bridge's inbox messages**

`UniversalBridgeMailbox.readMessage` · Confidence: 80

**Description**
`readMessage` is gated only by `onlyBridge` and operates on a single shared `inbox` keyed by `(chainSrc, chainDest, sender, receiver, sessionId, label)`. Any authorized bridge can read — and `consumedKeys[key] = true` — a key that belongs to a different bridge, marking the message as already consumed. The legitimate recipient bridge then reverts with `MessageAlreadyConsumed`, allowing one malicious or compromised authorized bridge to permanently grief every other bridge sharing the mailbox.

**Fix**

```diff
- mapping(bytes32 key => bytes message) public inbox;
+ mapping(address bridge => mapping(bytes32 key => bytes message)) public inbox;
+ // and key the consumedKeys / createdKeys maps the same way, or include the
+ // intended recipient bridge in getKey()
```

Or restrict `readMessage` so that `header.receiver` (or a per-key authorized reader recorded at `putInbox`) must match `msg.sender`'s authorized scope.

---

## Below-threshold Findings

[78] **11. `UniversalBridgeMailbox.writeMessage` silently overwrites existing outbox entries**

`UniversalBridgeMailbox.writeMessage` · Confidence: 78

**Description**
Unlike `putInbox`, which reverts on `createdKeys[key]`, `writeMessage` re-writes `outbox[key]` and `createdKeys[key] = true` without any duplicate check, so a bridge calling twice with the same `(sender, receiver, sessionId, label)` silently replaces the first payload — corrupting the outboxRoot accumulator and any in-flight session that relies on the first message.

---

[75] **12. `ComposeL2ToL2Bridge.redeemWrappedCET` allows free mint of "core" CET supply**

`ComposeL2ToL2Bridge.redeemWrappedCET` · Confidence: 75

**Description**
`redeemWrappedCET` burns a `wrappedCET` (which represents value locked on a remote chain) and mints `coreCET` 1:1 on this chain via `crosschainMint`. Because `coreCET.cetType == CORE` means `remoteAsset == address(coreCET)`, no remote escrow exists to back this newly minted core supply — the function inflates total supply of the "home" CET on this chain by the wrapped amount with no offsetting lock anywhere. Trail not fully complete: depends on whether any "core" CET is intended to ever coexist on a chain that also receives a wrapped form, and on the trust model of the wrapped-CET source chain.

---

[75] **13. `USDC_SSV_WETH_Swapper.swap` is missing slippage protection and reentrancy guard**

`USDC_SSV_WETH_Swapper.swap` · Confidence: 75

**Description**
`swap` computes `amountOut` from on-chain reserves and executes without a `minAmountOut` parameter and without a reentrancy guard; uses raw `transfer`/`transferFrom` without checking return values. A token with a transfer hook (or any "core" CET that the swapper later supports) can re-enter `swap` mid-execution to drain the pool, and ordinary users have no protection against sandwich loss. The contract has no SafeERC20 either, so non-standard tokens (USDT-style no-return) revert.

---

[70] **14. `ComposeDisputeGame.lastSuperblockNumber` is per-clone — global monotonicity belongs to the ASR (demoted)**

`ComposeDisputeGame.initialize` · Confidence: 70

**Description**
The `lastSuperblockNumber` field lives in clone storage, which is uninitialized on every new game, so the in-game ordering check is effectively `aggOutputs.superblockNumber > 0`. Global monotonicity is enforced by `ComposeAnchorStateRegistry.setAnchorState` via `game.l2SequenceNumber() <= anchorL2BlockNumber`, so this is a redundant/misleading check, not an exploitable replay (downgraded from the prior High in `scv-scan.md`).

---

[65] **15. `ComposeDisputeGame.initialize()` is `payable` but no bond is enforced or refundable**

`ComposeDisputeGame.initialize` · Confidence: 65

**Description**
`initialize()` accepts `msg.value` without verifying it equals the configured init bond and without storing it for refund; ETH sent to `initialize()` is permanently stuck in the clone (no `receive`/`fallback`/withdrawal). Code smell rather than direct theft, since the proposer is the only caller and would only self-grief.

---

## Rejected (with refutation)

- **`ComposeDisputeGame.resolve()` external without access control.** `resolve()` only succeeds when `status == GameStatus.IN_PROGRESS`. If an attacker calls `resolve()` before `initialize()`, `initialize()` later overwrites `status = GameStatus.IN_PROGRESS` (line 64) and re-resolves at line 150, so the attacker's premature resolution is wiped. If the legitimate proposer never calls `initialize()`, `createdAt` stays 0 and `ComposeAnchorStateRegistry.isGameRetired` returns `0 <= retirementTimestamp == true`, so `isGameProper` (and therefore `setAnchorState`) reject the game. Combined with the `wasRespectedGameTypeWhenCreated` flag also remaining `false`, no path lets a fraudulent resolved game become an anchor. (Was High #2 in `scv-scan.md`; rejected at Gate 2.)

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1  | [95] | `BridgeableToken.burn`/`mint` unrestricted |
| 2  | [95] | `USDC_SSV_WETH_Swapper.withdrawTokens` unrestricted |
| 3  | [90] | `SSVMintable`/`USDCMintable` unrestricted `mint`/`burn` |
| 4  | [90] | `ComposeL2ToL2Bridge` outbound bridge always reverts on `checkAck` |
| 5  | [88] | `CetFactory` re-authorizes revoked bridges on every new CET |
| 6  | [85] | `ComposeERC20Lockbox.migrateLiquidity` does not move accounting |
| 7  | [82] | Fee-on-transfer accounting break in `ComposeERC20Lockbox.lockERC20` |
| 8  | [82] | `L2ComposeBridge.onlyEOA` excludes smart wallets / AA |
| 9  | [82] | `CetFactory._authorizeAllBridges` unbounded loop |
| 10 | [80] | `UniversalBridgeMailbox.readMessage` cross-bridge consumption DoS |
| 11 | [78] | `UniversalBridgeMailbox.writeMessage` silent overwrite |
| 12 | [75] | `ComposeL2ToL2Bridge.redeemWrappedCET` free mint of core CET |
| 13 | [75] | `USDC_SSV_WETH_Swapper.swap` no slippage / reentrancy guard / SafeERC20 |
| 14 | [70] | `ComposeDisputeGame.lastSuperblockNumber` redundant per-clone check |
| 15 | [65] | `ComposeDisputeGame.initialize()` payable with no bond |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. Not scored._

- **`ComposableERC20.crosschainBurn(from, amount)` permits any authorized bridge to burn any user's balance** — `ComposableERC20.crosschainBurn` — Code smells: ERC-7802 spec compliance gives bridges blanket burn authority with no per-user allowance check; safe today because `L2ComposeBridge` and `ComposeL2ToL2Bridge` both pass `_from = msg.sender`, but any future authorized bridge that takes `_from` from user calldata immediately becomes a token-drain primitive across every CET in the system. Recommend adding a per-user allowance/permit on top of the ERC-7802 surface or auditing every bridge with burn authority.
- **`Mailbox.write` (L2 core) is permissionless and has no key-collision guard** — `Mailbox.write` — Code smells: unlike `UniversalBridgeMailbox`, `Mailbox.write` is callable by any address (no `onlyBridge`), and silently overwrites `outbox[key]` and `createdKeys[key]`. If anything downstream uses `outboxRootPerChain` or `messageHeaderListOutbox` for inclusion proofs, an attacker can corrupt the outbox view at zero cost. Trail: confirm whether the coordinator only consumes outbox entries from authorized senders or trusts the on-chain root.
- **`ComposeETHLockbox.unlockETH` enforces `sender.l2Sender() != DEFAULT_L2_SENDER` but does not pin it to the withdrawal target** — `ComposeETHLockbox.unlockETH` — Code smells: the only guard that this is a "real" finalize is the parent OP portal's transient `l2Sender`. If an attacker can cause the parent to enter the finalize path with a controlled withdrawal target that itself calls back into `unlockETH` for an unrelated victim's funds, the bound is loose. Worth tracing alongside `ComposePortal._isUnsafeTarget`.
- **`ComposeAnchorStateRegistry.setAnchorState` is permissionless** — `ComposeAnchorStateRegistry.setAnchorState` — Code smells: relies entirely on `isGameClaimValid` (registered + not blacklisted + not retired + not paused + respected + finalized + DEFENDER_WINS). Any flaw in `IFaultDisputeGame.wasRespectedGameTypeWhenCreated` (which on `ComposeDisputeGame` is regular storage settable only inside `initialize`) directly compromises the anchor. Already partly de-risked by the rejection of finding #2 above, but worth re-verifying for clones built off other game types.
- **`ComposeL1Bridge._initiateBridgeERC20` does not validate `(localToken, remoteToken)` pair** — `ComposeL1Bridge._initiateBridgeERC20` — Code smells: caller-supplied `_remoteToken` is forwarded to L2 verbatim, and L1 has no on-chain registry. Safety relies on the L2 side rejecting mismatched pairs (`L2ComposeBridge.finalizeBridgeERC20` does check `predictAddress(_remoteToken, l1ChainId) == _localToken` — confirms safe today). If L2 ever loosens that check, deposits become forge-able.
- **`UniversalBridgeMailbox` getKey collisions between inbox and outbox over self-loops** — `UniversalBridgeMailbox.getKey` — Code smells: `getKey` does not include a domain separator distinguishing inbox vs outbox; for `chainSrc == chainDest == block.chainid` (intra-chain test/dev paths) `writeMessage` and `putInbox` produce the same hash and write to the same `createdKeys`, allowing one side to DoS the other. Low impact unless intra-chain messaging ships.

---

> This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended.
