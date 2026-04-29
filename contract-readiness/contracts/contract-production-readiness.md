# Ethera Santander PoC - Contract Production Readiness Draft

**Date:** 2026-04-29
**Scope:** Contract-side work needed to move the Santander PoC toward production readiness.
**Focus areas:** deployment scripts, fork rehearsals, deployment metadata, integration tests, fuzzing/invariants, contract security hardening, and the AA/paymaster service dependency that Santander relies on.

## Sources

- Ethera contracts: this repo
- Ethera deployments: [ethera-deployments](https://github.com/ethera-labs/ethera-deployments)
- Ethera paymaster service: [paymaster-service](https://github.com/ethera-labs/paymaster-service)
- Ethera specs: [specs](https://github.com/ethera-labs/specs/tree/universal-bridge)
- Santander PoC notes: ethera-santander-poc-internal.md
- Internal conversation notes: discord_conversations.md
- SSV comparison material: MAINNET_READINESS.md, tests and deployments infra
- Account abstraction reference:
  - `https://github.com/eth-infinitism/account-abstraction/releases`

## Current Baseline

Yurii confirmed the Universal Bridge supports both M1 and M2. The UI demo only covers `L1 -> L2 -> L2 -> L1`, so it does not demonstrate native L2 tokens. Yurii also confirmed `ComposeL2OutputOracle` is deprecated in favor of dispute games.

Santander PoC flows confirmed as working:

- `L1 -> Rollup A ERC20`
- `L1 -> Rollup A ETH`
- `Rollup A -> Rollup B ERC20/CET`
- `Rollup A -> Rollup B ETH`
- `Rollup B -> L1 ERC20/CET withdrawal`
- `Rollup B -> L1 ETH withdrawal`

Local test baseline from this pass:

- `ethera-contracts/L2`: `forge test` passes, 53 tests passed.
- `ethera-contracts/L1-settlement`: `forge test` fails before contract logic because `networks.toml` is missing. This is a reproducibility issue: a clean checkout cannot run the L1 suite without manually copying/configuring local network config.
- `ethera-paymaster-service`: separate repo with a UUPS `SignatureVerifyingPaymasterV07` contract plus a Fastify JSON-RPC signing service.

AA/paymaster findings from repo inspection:

- The inspected paymaster repo currently shows protocol drift: docs/admin flows still describe ERC-4337 v0.7, but the runtime sponsorship handlers in `src/relay.ts` only accept `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`, i.e. a v0.8/v0.9-style EntryPoint address.
- The backend EIP-712 signing domain and payload in `src/relay.ts` no longer obviously match the current on-chain contract after the documented audit fixes. The service signs domain `SSVPaymasterECDSASigner` version `1`, while the contract expects `SignatureVerifyingPaymaster` version `5`, and the signed field set differs.
- The service currently has no visible request authentication, sponsorship allowlist, quota, or rate limiting. CORS is open to `*`.
- The service/admin scripts assume a single `PROXY_ADDRESS` environment variable despite chain-routed endpoints for `hoodi`, `rollupA`, and `rollupB`.
- The checked-in Docker path is not reproducible as written: it installs production dependencies only, then runs `npm start`, which depends on `ts-node` from devDependencies.
- Hardhat network config remains Base/Base Sepolia-centric even though helper code advertises `hoodi`, `rollupA`, and `rollupB` support.

## Recommendation

The highest return work is integration testing plus reproducible deployment/fork scripts.

Unit tests already exist for many contract-level paths, and the L2 Universal Bridge tests cover useful scenarios. The production-readiness gap is that the full Santander flow is not yet packaged as a repeatable test and deployment rehearsal: deploy or load real addresses, fork, run the canonical bridge path, verify balances/messages/metadata, and produce auditable output.

That gap now clearly includes the AA/paymaster layer. Santander does not only depend on bridge and settlement contracts; it also depends on a separate online paymaster signer/service. Production readiness therefore needs one coherent artifact set across on-chain contracts, AA addresses, paymaster service configuration, and entrypoint versioning. Otherwise the PoC can look healthy at the bridge layer while failing at UserOp sponsorship or remaining operationally unsafe.

The team-agreed deployment registry is [ethera-deployments](https://github.com/ethera-labs/ethera-deployments). Production-readiness work should respect that structure and format. The SSV deployment repo is useful as a process reference for runbooks, fork rehearsal, verification, attestations, and SAFE batches, but Ethera should not switch to the SSV output layout unless the team decides to change the registry.

For Santander, `sepolia-prod` is the canonical production-like environment for now. Owners are currently EOAs, but the deployment process should be ready for customer-owned multisigs. The target should be flexible without becoming heavy: if Santander decides to use SAFE, the expected owner/executor should be a config value and the same deployment flow should produce a SAFE batch instead of requiring a separate manual process.

Fuzzing is worth doing, but only after the invariants are explicitly defined. For Ethera, the invariants are not generic Solidity properties; they need to express bridge custody, CET supply, mailbox consumption, L1/L2 accounting, and proof/dispute assumptions.

## Priority Summary

| ID | Category | Priority | Item |
|---|---|---:|---|
| TEST-1 | Test | P0 | Add canonical Santander end-to-end integration tests |
| SCRIPT-1 | Scripts | P0 | Create reproducible deploy/upgrade/fork runbook and recipes around `ethera-deployments` |
| SCRIPT-2 | Scripts | P0 | Fix clean-checkout test and script reproducibility |
| SECURITY-1 | Security | P0 | Remove or gate deprecated production paths |
| SECURITY-4 | Security | P0 | Reconcile paymaster protocol, signature, and EntryPoint version drift |
| TEST-2 | Test | P1 | Add fork/rehearsal tests against deployed PoC environments |
| SCRIPT-3 | Scripts | P1 | Make `ethera-deployments` the canonical metadata source |
| OPS-1 | Operations | P1 | Add post-deploy health checks |
| OPS-2 | Operations | P1 | Harden paymaster service operations, key management, and sponsorship policy |
| SECURITY-2 | Security | P1 | Review access control and admin ownership |
| SCRIPT-5 | Scripts | P1 | Support both EOA and multisig deployment execution |
| SECURITY-3 | Security | P1 | Migrate Account Abstraction stack from v0.7 to v0.9 and track it as a pinned dependency |
| SECURITY-5 | Security | P1 | Validate and fix credible Solidity audit findings |
| TEST-3 | Test | P1 | Add negative-path integration tests |
| TEST-4 | Test | P1 | Strengthen L1 settlement/dispute-game integration tests |
| TEST-5 | Test | P1 | Add end-to-end AA/paymaster compatibility tests |
| FUZZ-1 | Fuzzing | P1 | Define contract-level invariants before fuzzing |
| FUZZ-2 | Fuzzing | P2 | Build stateful fuzz harnesses from the invariants |
| CI-1 | CI | P2 | Add CI jobs for static analysis, coverage, gas, and optional env-fork checks |
| SCRIPT-4 | Scripts | P2 | Add SAFE batch and deployment attestation outputs |
| QUALITY-1 | Quality | P2 | Reorganize tests and setup contracts |
| BUG-1 | Bug | P2 | Fix known compiler warnings and stale/deprecated names |
| DOC-1 | Docs | P2 | Create contract SPEC/FLOWS docs for the current implementation |
| GAS-1 | Gas | P3 | Define gas budgets for production-relevant bridge paths |
| RELEASE-1 | Release | P3 | Define deployment tagging/release convention for multi-customer PoCs |

## Items

### [TEST-1] Canonical Santander end-to-end integration tests

**Category:** Test
**Priority:** P0
**Status:** Pending

**Detail:**
Create a single integration suite that executes the exact Santander production story from a user perspective:

- L1 deposit of ERC20 to Rollup A.
- L1 deposit of ETH to Rollup A.
- Rollup A to Rollup B transfer of ERC20/CET.
- Rollup A to Rollup B transfer of ETH.
- Rollup B withdrawal of ERC20/CET back to L1.
- Rollup B withdrawal of ETH back to L1.

The test should assert custody and supply at every step: L1 lockbox balances, L2 bridge escrow balances, CET mint/burn totals, user balances, message payload fields, and final L1 withdrawal accounting. This is more important than adding more isolated unit tests because it validates the contract composition that Santander actually uses.

### [SCRIPT-1] Reproducible deploy/upgrade/fork runbook and recipes around `ethera-deployments`

**Category:** Scripts
**Priority:** P0
**Status:** Pending

**Detail:**
Use [ethera-deployments](https://github.com/ethera-labs/ethera-deployments) as the target registry and output format. Current agreed structure:

```text
contracts/
  <env>/
    L1/addresses.toml
    L2/addresses.toml
```

Representative environments are `sepolia-prod`, `hoodi-prod`, and `hoodi-stage`. The TOML files already use sections such as `[CodeReference]`, `[Shared_Infra]`, `[RollupA]`, and `[RollupB]`, with addresses for `ComposePortal`, `ComposeL1Bridge`, `ComposeL2Bridge`, `CetFactory`, `UniversalBridgeMailbox`, `ComposeL2ToL2Bridge`, and `ComposeETHLiquidity`.

The task is not to replace this with SSV's deployment output layout. The task is to build reliable scripts around this registry:

Minimum recipes:

- Deploy shared L1 infrastructure.
- Deploy or configure L2 Universal Bridge stack for rollups that may be managed by third parties.
- Upgrade/migrate a rollup to the current bridge/settlement contracts.
- Write or update the matching `ethera-deployments/contracts/<env>/<layer>/addresses.toml` files.
- Run the same operation on a fork using the same env/layer naming.
- Verify post-deploy state by reading the TOML files and checking chain state.
- Run the Santander integration suite against forked deployment state loaded from `ethera-deployments`.

At minimum, define two deployment tracks:

- **Shared L1 infra:** controlled by Ethera/SSV-side operators initially, but eventually possibly managed through multisig. This covers shared dispute/anchor/lockbox/portal infrastructure and any common L1 contracts.
- **L2 rollup deployments:** potentially managed by the customer or third-party rollup operator. Scripts should make the required owner, coordinator, mailbox, bridge, CET factory, and liquidity addresses explicit in config, without assuming the Ethera team controls every key.

Each track should support both direct EOA execution and prepared multisig execution. The same config should drive both modes where possible.

The existing `L1-settlement` justfile is a good start for recipes. The L2 side appears older and still references older bridge/demo contracts in places, so it needs to be brought up to the Universal Bridge stack and made compatible with the `ethera-deployments` registry.

### [SCRIPT-2] Clean-checkout test and script reproducibility

**Category:** Scripts
**Priority:** P0
**Status:** Pending

**Detail:**
`L1-settlement/forge test` currently fails because `networks.toml` is missing. Tests should not require a developer-private production config to run.

Options:

- Add a test-only config fixture that is copied or loaded automatically by tests.
- Make test setup read `test/networks.test.toml` instead of `networks.toml`.
- Add a `just test` recipe that prepares the local test config deterministically.

This should be fixed before using the L1 test result as a readiness signal.

### [SECURITY-1] Remove or gate deprecated production paths

**Category:** Security
**Priority:** P0
**Status:** Pending

**Detail:**
`ComposeL2OutputOracle` is still present but deprecated in favor of dispute games. The repo also still has older bridge/mailbox/demo artifacts and L2 deployment metadata around `Mailbox`, `StagedMailbox`, `Bridge`, `BridgeableToken`, and `PingPong`.

Production scripts and docs should make it impossible to accidentally deploy or verify the old path as the Santander production path. If the old contracts must remain for historical tests, label them clearly and keep them out of production recipes.

### [SECURITY-4] Reconcile paymaster protocol, signature, and EntryPoint version drift

**Category:** Security
**Priority:** P0
**Status:** Pending

**Detail:**
The inspected `ethera-paymaster-service` repo currently shows incompatible or at least ambiguous assumptions between docs, runtime, and contract implementation.

Observed drift to resolve:

- README/admin flows still describe the system as v0.7-oriented.
- Route setup and several scripts still use `ENTRYPOINT_ADDRESS_V07`.
- Sponsorship methods in `src/relay.ts` only accept `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`.
- Backend EIP-712 domain and version do not match the current contract constants.
- Backend signs a payload shape that appears different from what `SignatureVerifyingPaymasterV07` currently verifies on-chain.
- Admin/status tooling is also stale, for example `check-paymaster-status.ts` tries to read getters that are not present in the inspected contract file.

This is a P0 because Santander cannot safely depend on the AA sponsorship path until the team can point to one canonical combination of:

- paymaster contract commit and deployed proxy address,
- paymaster service commit and deployment URL,
- exact EntryPoint version/address,
- exact EIP-712 domain and signed fields,
- matching SDK/bundler configuration.

Acceptance direction:

1. Freeze the canonical Santander AA/paymaster branch/commit set.
2. Produce a golden test vector proving backend-generated signatures validate against the deployed contract.
3. Remove or clearly gate unsupported EntryPoint paths and stale docs/scripts.
4. Record the canonical configuration in `ethera-deployments` and post-deploy health checks.

### [TEST-2] Fork/rehearsal tests against deployed PoC environments

**Category:** Test
**Priority:** P1
**Status:** Pending

**Detail:**
Add a fork/rehearsal layer that consumes deployment metadata, preflights addresses, and runs the canonical Santander flows against forked Hoodi or Sepolia PoC state. This is not a mainnet-fork requirement because there are no Ethera mainnet contracts deployed yet.

The value is still real: it can catch issues that local mocks cannot catch, such as wrong proxy implementation, wrong owner, stale deployment metadata, missing ETH liquidity, wrong bridge authorization, or mismatched chain/domain IDs.

SSV's fork testing pattern is useful as a process reference: validate deployed state first, then run deterministic integration tests. For Ethera's current stage, these checks can start as manual or scheduled Hoodi/PoC rehearsals rather than mandatory PR-gating CI.

### [SCRIPT-3] Make `ethera-deployments` the canonical metadata source

**Category:** Scripts
**Priority:** P1
**Status:** Pending

**Detail:**
Deployment information is split between `ethera-contracts` JSON outputs and `ethera-deployments` TOML/ABI files. The team has agreed to use `ethera-deployments`, so contract scripts and tests should treat it as the canonical source of truth per environment.

Keep the existing TOML shape, but consider standardizing and filling gaps across all environments:

- `[CodeReference]`: contract commit SHA and source URL. This exists in `sepolia-prod`; it should be present everywhere.
- `[Shared_Infra]`: shared L1 admins, owners, verifier, lockboxes, dispute factory, anchor registry, and implementations.
- `[RollupA]` / `[RollupB]`: L1 rollup contracts in `L1/addresses.toml` and L2 bridge/mailbox/liquidity contracts in `L2/addresses.toml`.
- Dedicated AA/paymaster sections per rollup: EntryPoint version/address, SenderCreator, Kernel implementation, account factory, validator, paymaster proxy, paymaster service URL, signer, owner, and deposit/stake status.
- Consistent casing for layer folders and section names. Current repo has both `L2` and `l2` in environment folders.
- Explicit owner/coordinator fields for every L2 rollup section.
- Optional future fields if the team wants more auditability: implementation addresses, deployment tx hashes, block numbers, compiler version, bytecode hashes, ABI artifact version, and whether a contract is deprecated.

Scripts should read and write this format directly or generate a reviewed patch for it. Fork tests and post-deploy verification should consume this same registry instead of separate local JSON files.

### [OPS-1] Post-deploy health checks

**Category:** Operations
**Priority:** P1
**Status:** Pending

**Detail:**
Create read-only checks that prove the deployment is wired correctly before any demo or production usage:

- L1 bridge authorized by the expected portals/lockboxes.
- L2 bridge authorized to mint/burn CET tokens.
- `CETFactory` points to the expected implementation.
- L2 bridge knows the expected mailbox and other bridge/domain values.
- Account Abstraction `EntryPoint`, account factory, validator, paymaster, and SDK config all use the expected version.
- Paymaster service config matches the on-chain deployment per chain: proxy address, verifying signer, entrypoint version, and bundler URL.
- Paymaster deposit and stake/deposit thresholds are above the agreed operational minimum.
- ETH liquidity contracts are funded where required.
- Withdrawal delay/finality parameters match the intended environment.
- Dispute game / proof verifier config is non-zero and matches the runbook.
- Deprecated oracle path is not used by production deployment metadata.

These checks should be runnable after live deploy and after fork deploy.

### [OPS-2] Paymaster service operations, key management, and sponsorship policy

**Category:** Operations
**Priority:** P1
**Status:** Pending

**Detail:**
The paymaster service is an online signing dependency, so production readiness needs operational controls in addition to contract correctness.

Minimum hardening targets:

- Replace or wrap hot signer-key usage with a stronger custody model, such as KMS/HSM-backed signing or an equivalent isolated signer process.
- Define a signer rotation procedure, incident response, and emergency revoke path for the on-chain `verifyingSigner`.
- Add request authentication and sponsorship policy controls. At minimum, decide how callers are authenticated and what gets sponsored: allowlisted apps, specific accounts, contract targets, gas ceilings, or customer-specific quotas.
- Remove permissive defaults such as open CORS unless they are intentionally fronted by another authenticated gateway.
- Add operational alerts for low paymaster deposit, signer mismatch, failed sponsorship rate, bundler connectivity failure, and chain-specific config drift.
- Make the deployment path reproducible. The checked-in Dockerfile currently appears inconsistent with the `npm start` runtime dependency on `ts-node`.

Without this, Santander would rely on a sensitive hot-signing service with weak operational guardrails.

### [SECURITY-2] Access control and admin ownership review

**Category:** Security
**Priority:** P1
**Status:** Pending

**Detail:**
Document and test every privileged role:

- Proxy admin owner.
- Bridge owner/admin.
- Authorized bridge mappings.
- Lockbox authorized portals.
- Mailbox/coordinator roles.
- Dispute game factory and proposer-related roles.
- Guardian or pause roles if present.

The output should be an access-control matrix with the intended production owner for each role. Then add tests that unauthorized accounts cannot mutate bridge routing, mint/burn permissions, lockbox authorization, or settlement parameters.

Current assumption: ownership starts with EOAs, but customer-owned contracts are expected to move to SAFE or another multisig solution when required. The deployment process should not hardcode EOAs as the only viable model.

### [SCRIPT-5] Support both EOA and multisig deployment execution

**Category:** Scripts
**Priority:** P1
**Status:** Pending

**Detail:**
Use the SSV `UPGRADE_PLAYBOOK.md` as a process reference, but adapt it to Ethera's multi-customer model. The important pattern is:

- Config declares the intended owner/executor model.
- Scripts can execute directly when the owner is an EOA.
- Scripts can generate a multisig batch when the owner is SAFE or another multisig.
- The same deployment metadata and post-deploy verification are used in both modes.

This should apply to both shared L1 infrastructure and third-party/customer-managed L2 rollup deployments. The goal is not to overbuild governance tooling now. The goal is to avoid a restrictive deployment flow where moving from an EOA owner to a customer SAFE requires rewriting scripts or manually composing transactions.

Suggested config fields to evaluate:

- `execution_mode = "eoa" | "safe_batch"`
- `owner`
- `deployer`
- `safe_address`
- `customer`
- `environment`
- `scope = "shared_l1" | "rollup_l1" | "rollup_l2"`

Acceptance direction: if Santander chooses SAFE ownership, the team should be able to update config and run a just recipe that generates the reviewed batch, instead of inventing a new path.

### [SECURITY-3] Account Abstraction v0.7 to v0.9 migration and dependency tracking

**Category:** Security
**Priority:** P1
**Status:** Pending

**Detail:**
Ethera uses ERC-4337 account abstraction contracts deployed separately from `https://github.com/eth-infinitism/account-abstraction/tree/releases/v0.7`. There is an expected migration to v0.9 because of a discovered v0.7 vulnerability / security concern.

This should be treated as a production dependency and deployment artifact, not as an informal external setup.

Current state:

- Yurii confirmed the AA addresses are not saved in `ethera-deployments`.
- Current address source is a Google spreadsheet shared internally.
- Yurii confirmed current EntryPoint is `0x0000000071727De22E5E9d8BAf0edAc6f37da032`, the predefined v0.7 EntryPoint address on any chain.
- Local CSV reference Sepolia Ethrera Contracts - L1.csv contains Sepolia L1/shared/rollup addresses, but not the full AA stack.
- The inspected paymaster-service repo still shows unresolved drift between its documented v0.7 setup and its current runtime request handling and signature format.

Recommended practice:

- Pin the upstream Account Abstraction source to an exact tag and commit, for example `v0.9.0`, not a floating branch.
- Verify the upstream release notes, audit report, official EntryPoint address, SenderCreator address, and runtime bytecode hash before deployment.
- Keep a clear link from `ethera-contracts` to the pinned source. Options:
  - If Ethera compiles/deploys AA contracts from source, add a pinned git submodule or Foundry/npm dependency with lockfile.
  - If Ethera only verifies and records official deployments, keep a small checked-in manifest with repo URL, tag, commit, official addresses, expected code hashes, and verification commands.
- Record deployed AA addresses in `ethera-deployments` per environment and rollup. Current Santander notes mention `EntryPoint`, `Kernel`, `KernelFactory`, `MultiChainValidator`, and `Paymaster`, but the inspected TOML files do not yet expose a dedicated AA section.
- Include paymaster service URL and ownership/stake/deposit status because the AA contracts and off-chain paymaster service are operated together.
- Add post-deploy checks that verify the configured SDK/UI/bundler/paymaster all point to the same EntryPoint version.

Migration steps:

1. Export the AA spreadsheet into a reference CSV for historical reference.
2. Add canonical AA sections to `ethera-deployments` for `sepolia-prod` first.
3. Mark current AA version as v0.7 and record the current EntryPoint address.
4. Define the v0.9 target manifest before redeploying or switching SDK/bundler config.
5. Verify code hashes on every rollup before using the v0.9 EntryPoint in the PoC flow.

Suggested `ethera-deployments` TOML section:

```toml
[RollupA.AccountAbstraction]
Version = "v0.9.0"
SourceRepo = "https://github.com/eth-infinitism/account-abstraction"
Commit = "<exact-commit>"
EntryPoint = "0x..."
SenderCreator = "0x..."
KernelImplementation = "0x..."
KernelFactory = "0x..."
MultiChainValidator = "0x..."
Paymaster = "0x..."
PaymasterServiceURL = "https://..."
EntryPointCodeHash = "0x..."
Owner = "0x..."
Deployer = "0x..."
DeploymentBlock = 0
```

Open design point: use a submodule only if Ethera needs to compile/deploy directly from the upstream repo. If the deployment process only consumes the official AA release artifacts, a pinned manifest plus code-hash verification is simpler and less invasive.

### [SECURITY-5] Validate and fix credible Solidity audit findings

**Category:** Security
**Priority:** P1
**Status:** Pending

**Detail:**
The AI-assisted report in [solidity-auditor-report.md](../security/solidity-auditor-report.md) is not a final audit, but several findings check out against local source. See [solidity-auditor-triage.md](../security/solidity-auditor-triage.md) for the initial manual triage.

Items to convert into tests/fixes:

- `ComposeL2ToL2Bridge` ACK ordering: source send functions currently require an ACK already present in the inbox.
- `CETFactory` bridge revocation: revoked bridges remain in `bridgeList` and can be authorized on future CETs.
- `UniversalBridgeMailbox` message isolation and duplicate writes.
- `ComposeERC20Lockbox` migration accounting.
- `L2ComposeBridge.onlyEOA` compatibility with ERC-4337 smart accounts.

Old DEX/simple-bridge findings are real in code but should be handled mainly by production gating unless those contracts are still used in a customer environment.

### [TEST-3] Negative-path integration tests

**Category:** Test
**Priority:** P1
**Status:** Pending

**Detail:**
The happy-path tests are necessary but not sufficient. Add integration-level negative tests around:

- Message replay or double consumption.
- Wrong destination chain/domain.
- Wrong sender/receiver bridge.
- Missing send/ack pair.
- Mismatched CET `remoteAsset` or `remoteChainID`.
- Insufficient ETH liquidity on receive.
- Withdrawal finalization before maturity.
- Invalid proof or dispute-game state.
- Non-standard ERC20 behavior: fee-on-transfer, false return, missing metadata, reverting metadata.

These should be built around the same contracts as the happy-path suite, not just isolated mocks.

### [TEST-4] L1 settlement and dispute-game integration tests

**Category:** Test
**Priority:** P1
**Status:** Pending

**Detail:**
Strengthen tests around the current settlement path: dispute games, anchor state, portal finalization, lockboxes, and proof verification. Since `ComposeL2OutputOracle` is deprecated, the readiness test suite should prove the current path works without relying on oracle assumptions.

The target is not a full proving-system test. The target is contract integration confidence: output root consistency, proof verifier wiring, maturity delays, finalization gates, and lockbox accounting.

### [TEST-5] End-to-end AA/paymaster compatibility tests

**Category:** Test
**Priority:** P1
**Status:** Pending

**Detail:**
- Add end-to-end tests that validate the AA/paymaster layer against the deployed contract and paymaster service.
- Add a dedicated rehearsal suite that validates the actual Santander AA sponsorship path, not just isolated contract tests.

Minimum scenarios:

- Generate sponsorship data from the paymaster service for the configured rollup environment.
- Submit UserOps through the configured bundler against the intended EntryPoint version.
- Verify the on-chain paymaster accepts the service signature and the sponsored operation succeeds.
- Confirm the service rejects unsupported EntryPoint versions, wrong chain config, wrong paymaster address, stale signatures, and mismatched signer configuration.
- Run at least one rehearsal against Ethera-relevant environments, not only Base/Base Sepolia example paths.

### [FUZZ-1] Define contract-level invariants

**Category:** Fuzzing
**Priority:** P1
**Status:** Pending

**Detail:**
Do this before implementing fuzz harnesses. Suggested invariants:

- L1 escrowed token amount plus L2 native/CET supply equals the expected bridged supply for each asset.
- CET tokens can only be minted/burned by authorized bridge contracts.
- A mailbox message can be consumed at most once.
- L2-to-L2 transfer conserves value across source escrow/burn and destination release/mint.
- A CET address is deterministic for `(remoteChainID, remoteAsset, metadata)`.
- `remoteAsset` and `remoteChainID` cannot be spoofed during redemption or withdrawal.
- ETH bridge liquidity cannot go negative and cannot release more ETH than funded/escrowed.
- Lockbox accounting is isolated per asset and per authorized portal.
- L1 withdrawal finalization cannot bypass proof/dispute/finality requirements.

Once these are agreed, they become the foundation for fuzzing, scenario tests, and manual review.

### [FUZZ-2] Stateful fuzz harnesses

**Category:** Fuzzing
**Priority:** P2
**Status:** Pending

**Detail:**
After invariants are agreed, build stateful harnesses around realistic actors:

- L1 depositor.
- Rollup A user.
- Rollup B user.
- Sequencer/mailbox actor.
- Bridge admin.
- Malicious or non-standard token.

Start with the Universal Bridge accounting invariants. Add settlement/dispute fuzzing later if the state model is clear enough.

### [CI-1] CI for static analysis, coverage, gas, and optional env-fork checks

**Category:** CI
**Priority:** P2
**Status:** Pending

**Detail:**
The SSV repo has separate workflows for regular tests, fork tests, Echidna, Slither, coverage, and gas reporting. Ethera does not need to copy all of that immediately, but production readiness should include:

- L1 and L2 `forge test`.
- Coverage report.
- Static analysis with a reviewed allowlist.
- Gas report for bridge paths.
- Optional Hoodi/Sepolia env-fork check, preferably scheduled or manually triggered at first.
- Optional fuzz job once invariants are implemented.

Do not make fork checks a hard PR requirement until the PoC environment is stable enough and the team is comfortable with RPC availability, fork block selection, and deployment metadata freshness.

### [SCRIPT-4] SAFE batch and deployment attestation outputs

**Category:** Scripts
**Priority:** P2
**Status:** Pending

**Detail:**
For any production admin action, generate reviewable artifacts before execution:

- Deployment attestation with bytecode hashes, commit SHA, compiler settings, and config.
- SAFE Transaction Builder JSON for multisig actions.
- Read-only verifier output after execution.

This reduces operational risk and gives reviewers a stable artifact instead of asking them to inspect ad hoc script output.

### [QUALITY-1] Test organization cleanup

**Category:** Quality
**Priority:** P2
**Status:** Pending

**Detail:**
Some test functions live under `test/setup/*.sol`, especially `ComposeL2IntegrationSetup.sol` and `ComposeIntegrationSetup.sol`. Setup contracts should ideally provide fixtures/helpers, while actual test contracts should live in clearly named test files.

This is not a security blocker, but it makes coverage, discovery, and future maintenance harder. Move scenario tests into named integration files and keep setup contracts focused on fixture construction.

### [BUG-1] Compiler warnings and stale names

**Category:** Bug
**Priority:** P2
**Status:** Pending

**Detail:**
Fix low-effort compiler warnings and stale references before production review. Current examples:

- `UniversalBridgeMailbox.readMessage` has a local `message` variable shadowing the return variable.
- `ComposeL2OutputOracle` has unused parameters and is deprecated.
- Some setup tests can be marked `view`.
- L2 justfile/deployment metadata still references older demo bridge names.
- Paymaster admin/runtime tooling in the separate repo still has stale assumptions around EntryPoint versioning and contract getters.

These are not necessarily exploitable bugs, but they create noise and make real warnings easier to miss.

### [DOC-1] Contract SPEC/FLOWS docs for the current implementation

**Category:** Docs
**Priority:** P2
**Status:** Pending

**Detail:**
Create Ethera contract docs modeled after the SSV `SPEC.md` and `FLOWS.md`, but focused on the current Universal Bridge and settlement implementation.

Minimum content:

- Canonical L1-to-L2, L2-to-L2, and L2-to-L1 flows.
- Contract responsibility map.
- Message payload formats.
- Asset accounting rules for ETH, native ERC20, and CET.
- Deprecated paths.
- Invariants.
- Deployment and role matrix.

This will make future feature work safer because tests and scripts can point to a shared source of truth.

### [GAS-1] Gas budgets for bridge paths

**Category:** Gas
**Priority:** P3
**Status:** Pending

**Detail:**
Define named gas budgets for production-relevant operations:

- First L1-to-L2 ERC20 receive that deploys a CET.
- Subsequent L1-to-L2 ERC20 receive using existing CET.
- L2-to-L2 ERC20/CET send and receive.
- L2-to-L2 ETH send and receive.
- L2-to-L1 withdrawal initiation and finalization.

This is lower priority than correctness, but it matters for UI/SDK gas estimation and for preventing accidental regressions in message-heavy paths.

### [RELEASE-1] Deployment tagging/release convention for multi-customer PoCs

**Category:** Release
**Priority:** P3
**Status:** Pending

**Detail:**
SSV Network's release practice is a useful reference, but Ethera likely needs a different convention. SSV manages one main production protocol version, while Ethera is expected to support multiple bank/customer PoCs. The L1 shared infrastructure may be common, but rollup deployments, configuration, and even some contract variants may differ per customer.

Define a tagging and release convention that captures:

- Customer/project name, for example `santander`.
- Environment, for example `hoodi-stage`, `hoodi-prod`, `sepolia-prod`, or future customer-specific networks.
- Layer/scope, for example shared L1 infra vs Rollup A/B deployments.
- Contract code reference and deployment registry reference.
- Whether the deployment is a PoC, staging, production pilot, or mainnet production deployment.

Possible tag shape to evaluate:

- `santander/hoodi-prod/l1-shared/<version-or-date>`
- `santander/hoodi-prod/rollup-a/<version-or-date>`
- `santander/hoodi-prod/rollup-b/<version-or-date>`
- `shared/hoodi-prod/l1/<version-or-date>`

This may also imply a repo organization decision. If [ethera-deployments](https://github.com/ethera-labs/ethera-deployments) remains the canonical deployment registry, it may need a customer-aware structure rather than only `contracts/<env>/<layer>/addresses.toml`.

Example structure to consider:

```text
contracts/
  shared/
    <env>/L1/addresses.toml
  customers/
    santander/
      <env>/L1/addresses.toml
      <env>/L2/addresses.toml
```

This is not a blocker for contract correctness, but it should be decided before more PoCs accumulate. Each deployment tag or release should point reviewers to the contract commit in `[CodeReference]`, the matching `ethera-deployments` TOML files, deployment or migration notes, verification status, and known limitations.

## Open Questions

- Should production support native L2 token bridging now, or is it explicitly out of scope until after the UI demo path?
- Confirm whether every environment should include `[CodeReference]`; currently it is present in `sepolia-prod` but not in all Hoodi files inspected in this pass.
- Which exact contracts should be Santander-owned vs Ethera/shared-infra-owned when moving beyond the current EOA setup?
- Which multisig product should be supported first for customer-owned contracts: SAFE only, or a more generic transaction-batch abstraction?
- Should Account Abstraction be deployed from a pinned submodule/dependency inside `ethera-contracts`, or tracked as an external official deployment with a checked-in manifest and code-hash verification?
- What is the exact production replacement path for any remaining `ComposeL2OutputOracle` references?
- Which exact `ethera-paymaster-service` branch/commit and deployment URL is Santander using today, and is it the same codebase inspected here?
- Should Santander keep one deterministic paymaster proxy address across all chains, or record explicit per-chain paymaster addresses and service config?
