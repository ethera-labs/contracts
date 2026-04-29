# Ethera Current State

Date: 2026-04-29

This is a working digest from local materials only. It has not been verified against live RPCs.

## Source Material Read

- Protocol specs:
  - [ethera-specs/settlement_layer.md](https://github.com/ethera-labs/specs/blob/universal-bridge/settlement_layer.md)
  - [ethera-specs/superblock_construction_protocol.md](https://github.com/ethera-labs/specs/blob/universal-bridge/superblock_construction_protocol.md)
  - [ethera-specs/synchronous_composability_protocol.md](https://github.com/ethera-labs/specs/blob/universal-bridge/synchronous_composability_protocol.md)
  - [ethera-specs/universal_bridge.md](https://github.com/ethera-labs/specs/blob/universal-bridge/universal_bridge.md)
- Santander PoC:
  - ethera-santander-poc-internal.md
  - discord_conversations.md
- Implementation/deployment:
  - [ethera-contracts](../../)
  - [ethera-deployments](https://github.com/ethera-labs/ethera-deployments)
  - [ethera-paymaster-service](https://github.com/ethera-labs/paymaster-service)

## One-Paragraph Model

Ethera is Compose specialized for institutional/private rollup use cases. The architecture has private OP-style rollups, a Shared Publisher / DCH that coordinates atomic cross-rollup execution, mailbox contracts that record inter-rollup messages, universal bridge contracts for L1<->L2 and L2<->L2 asset movement, and L1 settlement contracts that verify aggregated proofs of rollup state and mailbox consistency.

## Protocol Design

### SCP: Synchronous Composability Protocol

SCP is a two-phase-commit style protocol for cross-rollup transactions.

- Users submit an `xTRequest`, a bundle of transactions targeting multiple rollups.
- The Shared Publisher starts an SCP instance with `StartSC`.
- Each sequencer filters the transactions for its own chain, simulates execution, traces mailbox reads/writes, and exchanges CIRC messages for cross-chain dependencies.
- Each sequencer votes commit/abort.
- The Shared Publisher decides commit only if all participating rollups vote yes; otherwise it aborts.
- If committed, sequencers include the local transaction bundle and mailbox-populating transactions in their block.

Important properties:

- Safety is close to 2PC: agreement and validity.
- Liveness depends on the Shared Publisher not crashing.
- Sequencer crash faults are tolerated; Byzantine behavior needs protocol rules, proofs, rotation, or slashing.
- Default SCP timeout is 3 seconds.

### SBCP: Superblock Construction Protocol

SBCP wraps SCP into a 12-second slot/block construction protocol.

- Sequencers build one L2 block per slot.
- The Shared Publisher starts slots, starts SCP instances while there is time, then sends `RequestSeal`.
- Sequencers publish their own L2 blocks to their own DA. The spec notes that old references to the SP publishing all L2 blocks are deprecated.
- The SP validates received blocks, CIRC consistency, and headers, then builds/publishes a superblock.
- If a superblock cannot be built, the same superblock number is retried and cross-chain requests are re-queued.

Key operational point:

- A missing chain can be excluded only if no included cross-chain transaction depends on it.

### Settlement Layer

The long-term settlement design is ZK-based.

- Each sequencer proves its L2 batch/range with a modified OP-Succinct range program.
- The range public value adds a `mailboxRoot`.
- Per-rollup aggregation produces `AggregationOutputs`.
- The Shared Publisher runs a network aggregation program that verifies rollup proofs and mailbox consistency across chains.
- L1 verifies one aggregated proof for a `SuperblockBatch`.

Mailbox consistency rule:

- For every chain pair, one chain's inbox root for the other must match the other chain's outbox root for it.

The specs explicitly identify liveness coupling as a concern: one late or missing proof can stall an interacting superblock set.

## Universal Bridge Design

The universal bridge replaces the earlier "simple bridge and bridgeable token" approach.

Main concepts:

- L1 is canonical custody for ETH and L1-native ERC20s.
- L2 representations are `ComposableERC20` / CET tokens, ERC-7802 compatible.
- L2 native ERC20s can move L2->L2 by locking on source and minting CET on destination.
- CETs move L2->L2 by burning on source and minting on destination.
- L2->L1 withdrawals burn CET and release canonical L1 collateral.
- A `CETFactory` deploys deterministic wrapper CETs using CREATE2 based on `(remoteAsset, remoteChainID)`.
- `UniversalBridgeMailbox` replaces/extends the old mailbox for bridge-specific messages and bridge-only read/write.

Important implementation detail:

- Destination-chain first use can require deploying a CET, so gas limits need to be high enough. In the conversation, a 200k L1->L2 gas limit failed for first USDC bridge; 2m worked.

## Santander PoC

The PoC is about two private bank rollups and tokenized deposit flows.

PoC goals:

- Real-time inter-bank transfers.
- Private DA and private sequencers per bank.
- Atomic settlement between bank rollups.
- Receiver-bank approval before accepting inbound transfers.
- A foundation for limits, netting, and public-chain integration later.

Money model:

- M1: base money, represented as ERC20 on Ethereum or rollups.
- M2: bank tokenized deposit, lives on one bank rollup and is bank-developed.

The written PoC spec says inter-bank transfer of M1. The Discord thread flags this as possibly wrong and asks whether the intended inter-bank transfer is actually M2.

Clarification from Yurii:

- Universal bridge supports both M1 and M2.
- The current UI demo works only with the `L1 -> L2 -> L2 -> L1` path.
- Therefore, the UI demo does not cover native L2 tokens.

Verification model:

- Receiving bank should not be forced to accept a transfer.
- The PoC extends 2PC with an external verification API hook.
- Before voting commit, the receiving bank sequencer calls the bank's API.
- Approval means vote commit; rejection means vote abort.

## Current Implementation Picture

Local contracts are at commit `91d4d61` in a detached HEAD in [ethera-contracts](../../).

There are two bridge generations in the contracts repo:

- Old/simple L2 bridge:
  - [L2/src/core/Bridge.sol](../../L2/src/core/Bridge.sol)
  - [L2/src/core/Mailbox.sol](../../L2/src/core/Mailbox.sol)
  - Requires tokens to be bridgeable: the bridge burns/mints the token directly.
- Universal bridge:
  - [L2/src/bridge/ComposeL2ToL2Bridge.sol](../../L2/src/bridge/ComposeL2ToL2Bridge.sol)
  - [L2/src/bridge/L2ComposeBridge.sol](../../L2/src/bridge/L2ComposeBridge.sol)
  - [L2/src/bridge/UniversalBridgeMailbox.sol](../../L2/src/bridge/UniversalBridgeMailbox.sol)
  - [L2/src/bridge/CETFactory.sol](../../L2/src/bridge/CETFactory.sol)
  - [L2/src/bridge/ComposableERC20.sol](../../L2/src/bridge/ComposableERC20.sol)
  - [L1-settlement/src/ComposeL1Bridge.sol](../../L1-settlement/src/ComposeL1Bridge.sol)
  - [L1-settlement/src/ComposePortal.sol](../../L1-settlement/src/ComposePortal.sol)
  - [L1-settlement/src/ComposeERC20Lockbox.sol](../../L1-settlement/src/ComposeERC20Lockbox.sol)

Settlement contracts include:

- [ComposeDisputeGame.sol](../../L1-settlement/src/ComposeDisputeGame.sol): verifies SP1 aggregation proof, validates super-root/output-root matching, emits L2 output and superblock events, then resolves.
- [ComposeL2OutputOracle.sol](../../L1-settlement/src/ComposeL2OutputOracle.sol): deprecated in favor of dispute games.
- [ComposeAnchorStateRegistry.sol](../../L1-settlement/src/ComposeAnchorStateRegistry.sol): OP-style anchor registry integration.

## Deployment Picture

The deployments repo has current address TOMLs for:

- Sepolia prod: [contracts/sepolia-prod](https://github.com/ethera-labs/ethera-deployments/tree/main/contracts/sepolia-prod)
- Hoodi prod: [contracts/hoodi-prod](https://github.com/ethera-labs/ethera-deployments/tree/main/contracts/hoodi-prod)
- Hoodi stage: [contracts/hoodi-stage](https://github.com/ethera-labs/ethera-deployments/tree/main/contracts/hoodi-stage)

Sepolia prod deployment records reference contracts commit `91d4d61`.

Sepolia prod L2 chain IDs from conversations:

- Rollup A: `555555`
- Rollup B: `666666`

Legacy Hoodi prod chain IDs from conversations:

- Rollup A: `11113`
- Rollup B: `22224`

## Account Abstraction / Paymaster Layer

There is a separate AA/paymaster repo at [ethera-paymaster-service](https://github.com/ethera-labs/paymaster-service).

- It contains an upgradeable ERC-4337 paymaster contract, [contracts/SignatureVerifyingPaymasterV07.sol](https://github.com/ethera-labs/paymaster-service/blob/main/contracts/SignatureVerifyingPaymasterV07.sol), and a Fastify JSON-RPC service that signs sponsorship approvals off-chain.
- The service entrypoint is [src/index.ts](https://github.com/ethera-labs/paymaster-service/blob/main/src/index.ts), with routes in [src/routes/index.ts](https://github.com/ethera-labs/paymaster-service/blob/main/src/routes/index.ts) and signing logic in [src/relay.ts](https://github.com/ethera-labs/paymaster-service/blob/main/src/relay.ts).
- Exposed HTTP surface is minimal: `/`, `/ping`, `/debug-sentry`, and `/rpc/v1/:chain`.
- Supported chain labels in code are `baseSepolia`, `base`, `hoodi`, `rollupA`, `rollupB`, `localhost`, and `hardhat`.
- The service uses hot environment keys for both `DEPLOYER_PRIVATE_KEY` and `TRUSTED_SIGNER_PRIVATE_KEY`, and signs paymaster data server-side.
- The README says the service is deployed to Railway and the Dockerfile exists locally, but there is no Ethera deployment registry entry yet for the service URL, image/version, or runtime configuration.

Important metadata gap:

- `ethera-deployments` currently captures bridge/settlement contracts, but not the AA/paymaster layer.
- The paymaster repo still expects one shared `PROXY_ADDRESS` environment variable, while the HTTP API is chain-routed via `:chain`.
- Santander notes already referenced AA components such as `EntryPoint`, `Kernel`, `KernelFactory`, `MultiChainValidator`, and `Paymaster`, but those addresses are not yet normalized into the current Ethera deployment registry.

Current implementation drift/risk identified from the repo:

- Repo/docs/admin scripts still present the system as ERC-4337 v0.7, but the live request handlers in `src/relay.ts` only accept `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108` for sponsorship methods, i.e. a v0.8/v0.9-style EntryPoint address, while route setup and several tasks still use `ENTRYPOINT_ADDRESS_V07`.
- The backend EIP-712 signing domain in `src/relay.ts` uses name `SSVPaymasterECDSASigner` and version `1`, while the current contract expects domain `SignatureVerifyingPaymaster` and version `5`.
- The backend signs a larger typed payload than the current contract verifies. The contract hash is based on `validUntil`, `validAfter`, `sender`, `nonce`, and `keccak256(callData)`, while the service signs additional gas-related fields. This needs explicit reconciliation before treating the Santander AA path as production-ready.
- The route layer currently has open CORS (`origin: "*"`) and no visible authentication, allowlist, quota, or sponsorship-policy checks.
- Hardhat deployment config is still Base/Base Sepolia-centric even though runtime helpers mention `hoodi`, `rollupA`, and `rollupB`.
- The Dockerfile installs production dependencies only but runs `npm start`, which depends on `ts-node` from devDependencies. That suggests the checked-in container path is not currently reproducible without further changes.
- `check-paymaster-status.ts` attempts to read `getDomainName()` and `getDomainVersion()`, but the current contract file only exposes `domainSeparator()` and `VERSION`. This is another sign that runtime/admin tooling is out of sync with the contract.
- `src/routes/index.ts` no longer reads `VERSION()` when setting up the handler because the check is commented out, so startup readiness does not currently prove that the configured paymaster contract matches the expected implementation.

## Conversation-Derived Status

The project moved through these states:

1. Initial Santander target was simple: A->B ERC20 bridge and simple M2 contract, excluding advanced scenarios.
2. Existing Compose/simple bridge was believed sufficient for early PoC because it can burn/mint bridgeable tokens.
3. L1<->L2 needed ERC20 lockbox support and Compose versions of L1/L2 bridge contracts.
4. Universal bridge became the desired end state because it removes the need for every token to be pre-authorized as bridgeable.
5. Universal bridge changes mailbox/sequencer assumptions, so switching it directly on Sepolia prod caused coordination risk.
6. Hoodi prod was used as a safer migration/test target.
7. Sepolia prod later received universal bridge changes, and the old bridge became unsupported by sequencers.

Known operational issues observed in the conversation:

- Publisher/prover output lag blocked L2->L1 prove/finalize. Cause cited: Succinct network migration from SP1 v6.0.x to v6.1.x.
- First-time L1->L2 ERC20/CET mint needed more gas because the CET contract is deployed on first bridge.
- L2->L2 CET path needed SDK gas overrides.
- L2->L2 ETH path failed when ETH liquidity was empty; funding `ComposeETHLiquidity` fixed it.
- Portal proof maturity delay was 7 days; for testnet/PoC the team agreed to reduce it aggressively, and Yurii later said he set cooldown to 0.
- Explorers lacked useful UserOp visibility, making AA/debugging hard.
- The Santander-facing webapp/main branch broke when sequencers switched from simple bridge to universal bridge before the universal-bridge branch was ready.

## Santander PoC Flow Status

Yurii confirmed the following flows are working on the Santander PoC stack:

- L1 -> Rollup A ERC20
- L1 -> Rollup A ETH
- Rollup A -> Rollup B ERC20/CET
- Rollup A -> Rollup B ETH
- Rollup B -> L1 ERC20/CET withdrawal
- Rollup B -> L1 ETH withdrawal

Important scope note:

- Universal bridge supports both M1 and M2.
- The current UI demo covers `L1 -> L2 -> L2 -> L1`.
- The UI demo does not cover native L2 token flows.

## Most Important Follow-Ups

1. Confirm current Sepolia prod bridge mode and sequencer compatibility.
2. Verify which webapp/SDK branch Santander is using now.
3. Verify final deployed proof maturity delays on both Sepolia prod portals.
4. Capture UI demo constraints and native L2-token limitations in Santander-facing docs.
5. Inventory the Santander AA/paymaster deployment per chain: paymaster proxy address, service URL, trusted signer, owner, deposit/stake state, and exact EntryPoint version.
6. Reconcile the paymaster-service runtime with the current contract implementation before treating ERC-4337 sponsorship as production-ready.
7. Add the AA/paymaster layer to `ethera-deployments` so Santander environments are reproducible end-to-end, not only for bridge and settlement contracts.
8. Triage and test the credible findings from [solidity-auditor-triage.md](../security/solidity-auditor-triage.md), especially ACK ordering, CET factory bridge revocation, mailbox message isolation, lockbox migration accounting, and AA compatibility.
