# Solidity Auditor Report Triage

**Date:** 2026-04-29
**Input report:** [solidity-auditor-report.md](solidity-auditor-report.md)
**Scope checked:** Selected high/medium findings against local `ethera-contracts` source.

## Summary

The AI-assisted report is useful, but it mixes three different classes of issues:

1. Real bugs in old/demo contracts that should not be in any production deployment path.
2. Real or likely-real issues in the current Universal Bridge / settlement path.
3. Design assumptions that need to be written down and tested rather than blindly treated as exploitable bugs.

My view: do not treat the report as a final audit, but do use it as a readiness input. The highest-value outcome is to convert the credible findings into regression tests and production gating rules.

## Highest Priority To Validate Or Fix

### 1. `ComposeL2ToL2Bridge` immediate ACK check may make normal L2-to-L2 sends impossible

**Status:** Likely valid, needs protocol confirmation.
**Production relevance:** High.

Evidence:

- [ComposeL2ToL2Bridge.sol](../../L2/src/bridge/ComposeL2ToL2Bridge.sol:111) writes `SEND_TOKENS`, then immediately calls `checkAck`.
- [ComposeL2ToL2Bridge.sol](../../L2/src/bridge/ComposeL2ToL2Bridge.sol:153) does the same for `bridgeCETTo`.
- [ComposeL2ToL2Bridge.sol](../../L2/src/bridge/ComposeL2ToL2Bridge.sol:299) consumes the ACK from the mailbox.
- Existing tests pre-populate the ACK before sending, for example [ComposeL2IntegrationSetup.sol](../../L2/test/setup/ComposeL2IntegrationSetup.sol:506), [ComposeL2IntegrationSetup.sol](../../L2/test/setup/ComposeL2IntegrationSetup.sol:689), and [ComposeL2IntegrationSetup.sol](../../L2/test/setup/ComposeL2IntegrationSetup.sol:774).

Why this matters:

If the intended runtime order is source send -> destination receive -> destination ACK -> source confirmation, then requiring the ACK inside the source send transaction is not viable. If the sequencer/coordinator intentionally preloads ACKs before user execution in the same atomic bundle, then this must be documented and tested as a sequencer-level contract. Right now, the contract tests hide the issue by placing the ACK in the inbox before calling the bridge function.

Action:

- Ask Yurii whether ACK pre-population is the intended protocol behavior.
- Add one negative test where no ACK is preloaded and document whether revert is expected.
- Add one end-to-end scenario test that follows the real sequencer/coordinator ordering.

### 2. `CetFactory` bridge revocation and bridge-list growth

**Status:** Valid.
**Production relevance:** High.

Evidence:

- [CETFactory.sol](../../L2/src/bridge/CETFactory.sol:26) pushes every authorized bridge into `bridgeList`.
- [CETFactory.sol](../../L2/src/bridge/CETFactory.sol:34) revokes only the mapping and does not remove the bridge from `bridgeList`.
- [CETFactory.sol](../../L2/src/bridge/CETFactory.sol:78) later authorizes every address in `bridgeList` on each newly deployed CET without checking the factory's current `authorizedBridges` mapping.

Impact:

A revoked bridge can be re-authorized on future CETs. Duplicate authorizations can also grow the list and increase gas for first-time CET deployment.

Action:

- Make `authorizeBridge` idempotent.
- Either remove revoked bridges from `bridgeList` or filter by `authorizedBridges[bridgeList[i]]` in `_authorizeAllBridges`.
- Add tests for revoke -> deploy new CET -> revoked bridge must not be authorized.

### 3. `ComposeERC20Lockbox.migrateLiquidity` does not migrate accounting

**Status:** Valid if migration is used.
**Production relevance:** Medium/high for ops.

Evidence:

- [ComposeERC20Lockbox.sol](../../L1-settlement/src/ComposeERC20Lockbox.sol:138) transfers all token balance to the destination lockbox.
- [ComposeERC20Lockbox.sol](../../L1-settlement/src/ComposeERC20Lockbox.sol:131) `receiveLiquidity` only emits an event and does not increment `totalDeposited`.
- [ComposeERC20Lockbox.sol](../../L1-settlement/src/ComposeERC20Lockbox.sol:89) source accounting is not decremented before migration.

Impact:

After migration, the destination can hold tokens but not have matching `totalDeposited` accounting, while the source can retain stale accounting. That can break later unlocks or invariants.

Action:

- Either remove migration from the production surface until needed, or fix accounting and test source/destination invariants.

### 4. `UniversalBridgeMailbox` authorization is too broad for multiple bridges

**Status:** Plausible and should be fixed or constrained.
**Production relevance:** Medium/high depending on number of authorized bridges.

Evidence:

- [UniversalBridgeMailbox.sol](../../L2/src/bridge/UniversalBridgeMailbox.sol:118) allows any authorized bridge to read any message if it knows the header.
- [UniversalBridgeMailbox.sol](../../L2/src/bridge/UniversalBridgeMailbox.sol:138) marks the key consumed globally.
- [UniversalBridgeMailbox.sol](../../L2/src/bridge/UniversalBridgeMailbox.sol:146) writes outbox messages without duplicate-key rejection.

Impact:

If more than one bridge is authorized, a compromised or buggy bridge can consume messages meant for another bridge. Duplicate writes can also overwrite the outbox mapping, even though the root history changes.

Action:

- Scope message consumption by intended bridge/receiver or keep one authorized bridge per mailbox.
- Add duplicate-key checks to `writeMessage`.
- Add tests for cross-bridge consumption and duplicate writes.

### 5. `L2ComposeBridge.onlyEOA` conflicts with Account Abstraction

**Status:** Valid product/protocol conflict.
**Production relevance:** Medium.

Evidence:

- [L2ComposeBridge.sol](../../L2/src/bridge/L2ComposeBridge.sol:113) rejects `msg.sender != tx.origin`.
- `bridgeETH` and `bridgeERC20` use `onlyEOA`, while `bridgeETHTo` and `bridgeERC20To` are callable by smart accounts.

Impact:

The PoC uses ERC-4337 smart accounts, so SDK/UI should use the `*To` functions. This is survivable but fragile. If docs/UI call the non-`To` variants from a smart account, they fail.

Action:

- Decide whether to remove `onlyEOA` or document that AA flows must always use `bridgeETHTo` / `bridgeERC20To`.
- Add AA-style integration tests for bridge calls.

## Real But Probably Legacy/Demo Cleanup

These findings are real in code, but likely belong under "remove/gate deprecated production paths" unless the contracts are still used.

- [BridgeableToken.sol](../../L2/src/core/BridgeableToken.sol:28): public `burn` and `mint` despite comments saying bridge-only.
- [USDC_SSV_WETH_Swapper.sol](../../L2/src/dex/USDC_SSV_WETH_Swapper.sol:86): unrestricted `withdrawTokens`.
- `SSVMintable` and `USDCMintable`: unrestricted mint/burn.
- `USDC_SSV_WETH_Swapper.swap`: no slippage parameter, no SafeERC20, no reentrancy guard.

Action:

- Keep them out of `ethera-deployments` production environments.
- Remove old DEX/simple-bridge just recipes from production runbooks, or mark them explicitly as demo-only.
- If any are still deployed in a customer environment, treat the corresponding issue as critical.

## Design Decisions To Specify

### Fee-on-transfer / rebasing tokens

`ComposeERC20Lockbox.lockERC20` accounts by requested `_amount`, not actual received amount. Given the portal first transfers `_amount` into the lockbox path, fee-on-transfer tokens will likely revert or break accounting. This is acceptable only if explicitly unsupported.

Action: document the supported-token policy. For Santander M1/M2, an allowlist of standard ERC20s is probably better than trying to support every ERC20 variant.

### `redeemWrappedCET`

The report flags possible free minting of core CET. I did not fully validate the intended asset model here. This should be converted into an invariant/spec question: under what circumstances can a wrapped CET and core CET coexist, and what collateral backs the conversion?

Action: define a CET supply/custody invariant before fuzzing this path.

### `ComposeDisputeGame` low-confidence items

The report's dispute-game findings are lower priority from this pass:

- `lastSuperblockNumber` being per-clone looks redundant if ASR enforces global monotonicity.
- `initialize()` being payable without bond accounting is probably self-grief unless callers are expected to post bonds.

Action: revisit during settlement-specific review, not as immediate Santander bridge blockers.

## Readiness Backlog Changes Suggested

- Add a specific audit-triage item for confirmed findings.
- Add tests for ACK ordering, CET factory revoke, mailbox duplicate/reader isolation, lockbox migration accounting, and AA bridge calls.
- Keep old DEX/simple-bridge contracts out of production deployment scripts and `ethera-deployments`.
