# Rollup Migration Guide

This guide covers migrating an existing OP Stack rollup to use Compose shared infrastructure
(shared dispute game, ETH lockbox, and anchor state registry).

---

## Overview

There are two migration paths depending on your rollup's current OP Stack version:

| Rollup version | Path | Command | Gas | Time |
|---|---|---|---|---|
| 3.x.x | V3 — full upgrade | `just l1-migrate-v3` | ~5–10M | 5–10 min |
| 4.x.x / 5.x.x | V4 — minimal migration | `just l1-migrate-v4` | ~500k | 1–2 min |

**V4 is idempotent** — each step checks current state and skips if already applied. Safe to re-run.

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [just](https://github.com/casey/just#installation)

After cloning, initialize submodules and build:

```sh
git submodule update --init --recursive
forge build
```

**Compose shared infrastructure** must already be deployed and `config.json` must have the `l1.deployed` section filled in. If you are joining an existing cluster (not the one who ran `just l1-deploy-shared`), ask the cluster operator for their `config.json` — the `l1.deployed.*` addresses are fixed for the cluster and shared by all rollups.

If you need to deploy shared infra yourself, see [Deploy Compose Bridge](deploy-compose-bridge.md) first.

Private keys required:
- **Rollup ProxyAdmin owner** — the address in `rollups.<name>.l1.proxyAdminOwner`
- **Compose ProxyAdmin owner** — the address in `l1.proxyAdminOwner`

---

## Step 1 — Detect rollup version

```sh
cast call <PORTAL_PROXY_ADDRESS> "version()(string)" --rpc-url <L1_RPC_URL>
```

- `3.x.x` → use `just l1-migrate-v3`
- `4.x.x` or `5.x.x` → use `just l1-migrate-v4`

---

## Step 2 — Configure config.json

`config.json` ships with a template entry keyed `chain-example`. Rename it to your rollup name
and fill in the `l1.*` fields with your existing OP Stack L1 contract addresses:

```json
{
  "rollups": {
    "chain-100003": {
      "chainId": "100003",
      "owner": "0x...",
      "coordinator": "0x...",
      "l1ChainId": "11155111",
      "l2Xdm": "0x4200000000000000000000000000000000000007",
      "create2Salt": "0x0000000000000000000000000000000000000000000000000000000000000001",
      "initialEthSeed": "0",
      "l1": {
        "portalProxy": "0x...",
        "portalImpl": "0x...",
        "proxyAdmin": "0x...",
        "proxyAdminOwner": "0x...",
        "systemConfig": "0x...",
        "l1CrossDomainMessenger": "0x...",
        "l1StandardBridge": "0x...",
        "l1ERC721Bridge": "0x..."
      }
    }
  }
}
```

All `l1.*` values are the existing OP Stack L1 contract addresses for this rollup.
The migration scripts will upgrade these contracts in-place.

`portalImpl` is the current implementation address behind the proxy (not the proxy itself). To find it:

```sh
cast storage <PORTAL_PROXY> 0x360894a13ba1a3210667c828492db98dca3e2076 --rpc-url <L1_RPC_URL>
```

`coordinator` is the address of the off-chain relayer for the `UniversalBridgeMailbox` (used
for L2↔L2 message routing). Required for L2 bridge deployment; can be any address for L1-only
migration.

---

## Step 3 — Configure .env

```sh
cp .env.example .env
```

Fill in:

```
ROLLUP_NAME=chain-100003
RPC_URL=https://<l1-rpc>

# Private key for rollups.<name>.l1.proxyAdminOwner — signs portal upgrades, ETH_LOCKBOX, super-roots migration
ROLLUP_OWNER_KEY=0x<rollup-proxy-admin-owner-private-key>

# Private key for l1.proxyAdminOwner — signs portal authorization in the shared lockbox
PROXY_ADMIN_OWNER_KEY=0x<compose-proxy-admin-owner-private-key>

# V3 only: key for deploying new implementation contracts (can be any funded wallet)
DEPLOYER_KEY=0x<deployer-private-key>
```

`ROLLUP_OWNER_KEY` must correspond to the address at `rollups.<name>.l1.proxyAdminOwner` in `config.json`.
`PROXY_ADMIN_OWNER_KEY` must correspond to `l1.proxyAdminOwner` (the Compose shared infra owner).

---

## V4 Migration (OP Stack 4.x / 5.x)

Minimal migration — only state updates, no contract upgrades (except auto-upgrading portal to
`OptimismPortalInterop` if it isn't already).

### Dry run first

```sh
just l1-migrate-v4 chain-100003 true
```

Simulates all steps without broadcasting. Outputs what each step would do and which keys are
required.

### Live run

```sh
just l1-migrate-v4 chain-100003
```

### What the script does

| Step | Action | Signer |
|---|---|---|
| 0 | Detect portal type. If not `OptimismPortalInterop`, deploy new impl and upgrade proxy | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 1 | Enable `ETH_LOCKBOX` feature in `SystemConfig` (skips if already enabled) | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 2 | Authorize portal in `ComposeETHLockbox` (skips if already authorized) | Compose ProxyAdmin owner (`PROXY_ADMIN_OWNER_KEY`) |
| 3 | Call `migrateToSuperRoots()` — sets new lockbox + ASR, enables super-roots mode, migrates ETH atomically (skips if already migrated) | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |

---

## V3 Migration (OP Stack 3.x)

Full upgrade — deploys new implementations for all rollup contracts and migrates to Compose.
Requires both rollup and Compose ProxyAdmin owner keys.

### Dry run first

```sh
just l1-migrate-v3 chain-100003 true
```

### Live run

```sh
just l1-migrate-v3 chain-100003
```

> **Note:** Step 2 sets `l2ChainId` on `SystemConfig` from the `chainId` field in `config.json`. Ensure `rollups.<name>.chainId` is correct before running.

### What the script does

| Step | Action | Signer |
|---|---|---|
| 1 | Deploy new V4 implementations (SystemConfig, OptimismPortalInterop, XDM, L1StandardBridge, L1ERC721Bridge) | `DEPLOYER_KEY` |
| 2 | Upgrade `SystemConfig` — sets `l2ChainId` and `superchainConfig` | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 3 | Enable `ETH_LOCKBOX` feature in `SystemConfig` | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 4 | Upgrade `OptimismPortal2` to `OptimismPortalInterop` impl | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 5 | Authorize portal in `ComposeETHLockbox` | Compose ProxyAdmin owner (`PROXY_ADMIN_OWNER_KEY`) |
| 6 | Upgrade `L1CrossDomainMessenger`, `L1StandardBridge`, `L1ERC721Bridge` | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |
| 7 | Call `migrateToSuperRoots()` + `migrateLiquidity()` atomically | Rollup ProxyAdmin owner (`ROLLUP_OWNER_KEY`) |

Steps 5 and 7 are combined into a single `migrateToSuperRoots()` call because `migrateLiquidity()` requires `ethLockbox` to be set first — both happen atomically in the same transaction.

---

## Post-migration verification

After a successful live run the script prints post-migration validation results. You can also
verify manually:

```sh
# ETH_LOCKBOX feature enabled
cast call <SYSTEM_CONFIG> "isFeatureEnabled(uint8)(bool)" 1 --rpc-url $RPC_URL

# Portal points to Compose ASR
cast call <PORTAL_PROXY> "anchorStateRegistry()(address)" --rpc-url $RPC_URL

# Portal points to Compose ETH lockbox
cast call <PORTAL_PROXY> "ethLockbox()(address)" --rpc-url $RPC_URL

# Super roots mode active
cast call <PORTAL_PROXY> "superRootsActive()(bool)" --rpc-url $RPC_URL

# Portal ETH balance migrated (should be 0)
cast balance <PORTAL_PROXY> --rpc-url $RPC_URL

# Portal authorized in lockbox
cast call <ETH_LOCKBOX> "authorizedPortals(address)(bool)" <PORTAL_PROXY> --rpc-url $RPC_URL
```

Expected results:
- `isFeatureEnabled` → `true`
- `anchorStateRegistry` → Compose ASR address from `config.json` (`l1.deployed.anchorStateRegistry`)
- `ethLockbox` → Compose lockbox address from `config.json` (`l1.deployed.ethLockbox`)
- `superRootsActive` → `true`
- `cast balance` → `0`
- `authorizedPortals` → `true`

---

## Phase 2 — Enable ERC-20 bridging (optional)

The migration above covers ETH settlement. To also enable ERC-20 deposits and withdrawals via
the shared `ComposeERC20Lockbox`, run `UpgradeToComposeBridge` after the migration completes.

This script:
- Upgrades the portal proxy to `ComposePortal`
- Deploys a `ComposeL1Bridge` proxy (the L1 counterpart of `L2ComposeBridge`)
- Deploys or reuses a `ComposeERC20Lockbox`
- Wires bridge ↔ portal ↔ lockbox authorizations

### 1. Create a config file for the upgrade

The script reads from a **separate JSON file** (not `config.json`). Keys must be in alphabetical order:

```json
{
  "composeAdminOwner": "0x...",
  "composeProxyAdmin": "0x...",
  "erc20LockboxProxy": "0x0000000000000000000000000000000000000000",
  "l1Xdm": "0x...",
  "portalProxy": "0x...",
  "rollupAdminOwner": "0x...",
  "rollupProxyAdmin": "0x...",
  "superchainConfig": "0x...",
  "systemConfig": "0x..."
}
```

| Field | Source |
|---|---|
| `composeAdminOwner` | `l1.proxyAdminOwner` in `config.json` |
| `composeProxyAdmin` | `l1.deployed.proxyAdmin` in `config.json` |
| `erc20LockboxProxy` | Zero address to deploy a new one; or pass an existing proxy address |
| `l1Xdm` | `rollups.<name>.l1.l1CrossDomainMessenger` in `config.json` |
| `portalProxy` | `rollups.<name>.l1.portalProxy` in `config.json` |
| `rollupAdminOwner` | `rollups.<name>.l1.proxyAdminOwner` in `config.json` |
| `rollupProxyAdmin` | `rollups.<name>.l1.proxyAdmin` in `config.json` |
| `superchainConfig` | `l1.deployed.superchainConfig` in `config.json` |
| `systemConfig` | `rollups.<name>.l1.systemConfig` in `config.json` |

Save the file as e.g. `upgrade-compose-bridge-<rollup>.json`.

**The ETH_LOCKBOX feature must already be enabled** (i.e., the migration above must have completed successfully) before running this script.

### 2. Run

```sh
just l1-upgrade-compose-bridge upgrade-compose-bridge-chain-100003.json true   # dry run
just l1-upgrade-compose-bridge upgrade-compose-bridge-chain-100003.json        # live run
```

This script broadcasts as **two addresses** — `rollupAdminOwner` and `composeAdminOwner`. Both
private keys must be passed:

```sh
# Alternatively, run forge directly with both keys:
forge script script/l1/deploy/UpgradeToComposeBridge.s.sol --sig "run(string,bool)" upgrade-compose-bridge-chain-100003.json false --private-key $ROLLUP_OWNER_KEY --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC_URL --broadcast --slow
```

### 3. Wire L1 ↔ L2 bridges

After deploying the L1 bridge and the L2 bridge (`just l2-deploy-bridge`), wire them together.
Set these in `.env`:

```
L1_COMPOSE_BRIDGE=0x<address from UpgradeToComposeBridge output>
L2_COMPOSE_BRIDGE=0x<address from just l2-deploy-bridge output>
COMPOSE_PORTAL=0x<portalProxy>
COMPOSE_ETH_LOCKBOX=0x<l1.deployed.ethLockbox>
```

Then run:

```sh
just l1-wire-bridges
```

This sets `ComposeL1Bridge.otherBridge` → L2 bridge and is idempotent (skips if already set).

---

## Standalone upgrade scripts

These scripts handle specific upgrade steps in isolation. Only needed outside a normal migration flow.

### `just l1-upgrade-portal-interop <rollup> [dryRun]`

Upgrades a standard `OptimismPortal2` to `OptimismPortalInterop` without running the full
migration. Useful if you want to separate the portal upgrade from the state migration, or if
step 0 of V4 migration failed and you want to retry it standalone.

Uses `ROLLUP_OWNER_KEY`.

### `just l1-upgrade-compose-portal <rollup> <proofMaturityDelay> [dryRun]`

Upgrades the portal proxy to `ComposePortal` with a given proof maturity delay. This is an
alternative to `UpgradeToComposeBridge` if you want to upgrade the portal implementation alone
without deploying the L1 bridge or ERC-20 lockbox.

Uses `ROLLUP_OWNER_KEY`.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `SystemConfig doesn't support ETH_LOCKBOX feature` | Rollup is still on V3 contracts | Use `just l1-migrate-v3` instead |
| `Portal upgrade verification failed` | New impl didn't deploy correctly | Check RPC connectivity and deployer balance |
| `L2 Chain ID not set` | `chainId` missing from rollup section in `config.json` | Add `chainId` field |
| `Compose ASR not set` | `l1.deployed.*` fields empty or contain placeholder `"0x..."` in `config.json` | Obtain the filled `config.json` from the cluster operator, or run `SAVE_DEPLOY_OUTPUT=true just l1-deploy-shared` |
| `Portal not authorized in lockbox` after migration | Ran dry run only, never ran live | Re-run without the `true` flag |
| `RollupConfig: ROLLUP_NAME not set` | `ROLLUP_NAME` env var missing or doesn't match a key in `config.json` | Check `.env` and that the rollup key in `config.json` matches exactly |
| `ETH_LOCKBOX feature not enabled` on `UpgradeToComposeBridge` | Phase 1 migration (`just l1-migrate-v4`) not completed | Complete the V4 migration first |
| `L1Bridge.otherBridge mismatch` on `just l1-wire-bridges` | `L1_COMPOSE_BRIDGE` already wired to a different L2 bridge | Check which L2 bridge was deployed; set `L2_COMPOSE_BRIDGE` to match |
