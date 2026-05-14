# Deploy Compose Bridge

This guide covers deploying the full Compose bridge stack: Phase 1 deploys shared L1 infrastructure
(one per cluster), Phase 2 deploys per-rollup L2 bridge contracts.

---

## Overview

```
Phase 1 — L1 shared infra (once per cluster)
  just l1-deploy-shared
  → ProxyAdmin, SuperchainConfig, DisputeGameFactory,
    ComposeAnchorStateRegistry, ComposeETHLockbox, ComposeDisputeGame
  → addresses written back to config.json under l1.deployed

Phase 2 — L2 bridge per rollup
  just l2-deploy-bridge <rollup>
  → CetFactory, UniversalBridgeMailbox, ComposeETHLiquidity,
    ComposeL2ToL2Bridge, L2ComposeBridge
  → wire to L1 bridge via just l2-wire-bridge

Phase 3 — Enable ERC-20 bridging (per rollup, after l1-migrate-v4)
  just l1-upgrade-compose-bridge <rollup>
  → ComposePortal, ComposeL1Bridge, ComposeERC20Lockbox (shared)
  → wire bridges via just l1-wire-bridges / just l2-wire-bridge
```

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [just](https://github.com/casey/just#installation)
- Funded deployer wallet (~0.5 ETH on L1 for Phase 1, small amount on each L2 for Phase 2)
- SP1 verifier address and aggregation vkey for the proof system

```sh
git submodule update --init --recursive
forge build
cp .env.example .env
```

---

## Phase 1 — L1 Shared Infrastructure

Deploy once per Compose cluster. All rollups that join the cluster will share these contracts.

### 1. Fill in config.json `l1.*` fields

```json
{
  "l1": {
    "guardian": "0x...",
    "proxyAdminOwner": "0x...",
    "authorizedProposer": "0x...",
    "sp1Verifier": "0x...",
    "aggregationVkey": "0x...",
    "proofMaturityDelaySeconds": 604800,
    "disputeGameFinalityDelaySeconds": 302400,
    "disputeGameInitBond": "80000000000000000",
    "deployed": {}
  }
}
```

| Field | Description |
|---|---|
| `guardian` | Address that can pause the SuperchainConfig |
| `proxyAdminOwner` | Owner of the shared ProxyAdmin (multisig recommended for production) |
| `authorizedProposer` | Address authorized to propose dispute games |
| `sp1Verifier` | SP1 verifier contract address on L1 |
| `aggregationVkey` | SP1 aggregation verification key (bytes32) |
| `proofMaturityDelaySeconds` | Delay before a proof is considered mature (7 days = 604800) |
| `disputeGameFinalityDelaySeconds` | Delay after game resolves before withdrawal is final (3.5 days = 302400) |
| `disputeGameInitBond` | Bond required to initialize a dispute game (wei) |

### 2. Set .env

```
PROXY_ADMIN_OWNER_KEY=0x<proxy-admin-owner-private-key>
GUARDIAN_KEY=0x<guardian-private-key>
RPC_URL=https://<l1-rpc>
```

### 3. Deploy

```sh
just l1-deploy-shared
```

Deployed addresses are written back into `config.json` under `l1.deployed` automatically. After a
successful run, `config.json` will have:

```json
{
  "l1": {
    "deployed": {
      "l1ChainId": 11155111,
      "proxyAdmin": "0x...",
      "superchainConfig": "0x...",
      "disputeGameFactory": "0x...",
      "anchorStateRegistry": "0x...",
      "ethLockbox": "0x...",
      "composeDisputeGame": "0x...",
      "erc20LockboxProxy": "0x0000000000000000000000000000000000000000"
    }
  }
}
```

`erc20LockboxProxy` starts as zero and is filled in automatically during Phase 3.

### What gets deployed

| Contract | Type | Description |
|---|---|---|
| `ProxyAdmin` | standalone | Owns all Compose proxies |
| `SuperchainConfig` | proxy | Guardian-controlled pause mechanism |
| `DisputeGameFactory` | proxy | Registers and creates dispute games |
| `ComposeAnchorStateRegistry` | proxy | Shared anchor state for all rollups |
| `ComposeETHLockbox` | proxy | Unified ETH liquidity pool |
| `ComposeDisputeGame` | implementation | SP1-based dispute game (game type 5555) |

---

## Phase 2 — L2 Bridge per Rollup

Deploy once per rollup L2. Uses CREATE2 with `create2Salt` from config so the cross-chain
contracts (`CetFactory`, `UniversalBridgeMailbox`, `ComposeETHLiquidity`, `ComposeL2ToL2Bridge`)
land at the **same address on every L2** — required for deterministic cross-rollup CET addresses
and message routing.

### 1. Add rollup section to config.json

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
      "l1": { ... }
    }
  }
}
```

| Field | Description |
|---|---|
| `owner` | Admin of all deployed L2 bridge contracts |
| `coordinator` | Off-chain relayer address for the `UniversalBridgeMailbox` |
| `l1ChainId` | Chain ID of the L1 this rollup settles to |
| `l2Xdm` | L2 CrossDomainMessenger predeploy (`0x4200...0007` on all OP Stack chains) |
| `create2Salt` | bytes32 salt — **must be identical across all rollups in the cluster** |
| `initialEthSeed` | Optional wei to pre-fund `ComposeETHLiquidity` at deploy time (0 = skip) |

### 2. Set .env

```
ROLLUP_OWNER_KEY=0x<rollup-owner-private-key>
RPC_URL=https://<l2-rpc>
```

`RPC_URL` must point at the **L2** RPC for this step. Scripts always read from `$RPC_URL` — there
is no per-rollup RPC field read from config.

If the L1 `ComposeL1Bridge` is already deployed, also set:
```
L1_COMPOSE_BRIDGE=0x<l1-compose-bridge-address>
```

Setting `L1_COMPOSE_BRIDGE` wires the L2 bridge to its L1 counterpart in the same deploy
transaction. If not set, run `just l2-wire-bridge` separately after both sides are deployed.

### 3. Deploy

```sh
just l2-deploy-bridge chain-100003
```

### What gets deployed

| Contract | Deploy method | Description |
|---|---|---|
| `CetFactory` | CREATE2 | Deploys and tracks Composable ERC-20 tokens (CETs) |
| `UniversalBridgeMailbox` | CREATE2 | Cross-rollup message routing |
| `ComposeETHLiquidity` | CREATE2 | ETH liquidity pool for L2↔L2 hops |
| `ComposeL2ToL2Bridge` | CREATE2 | Cross-rollup bridge (wired to mailbox + factory + liquidity) |
| `L2ComposeBridge` | CREATE (no salt) | Per-rollup L1↔L2 bridge |

### 4. Wire the L2 bridge (if L1_COMPOSE_BRIDGE was not set at deploy time)

After the L1 `ComposeL1Bridge` is deployed, wire the L2 side:

```sh
# Set in .env:
L2_COMPOSE_BRIDGE=0x<l2-compose-bridge-address>
L1_COMPOSE_BRIDGE=0x<l1-compose-bridge-address>

just l2-wire-bridge chain-100003
```

The script checks `otherBridge` on the L2 bridge and skips if already set. Reverts if the current
value is set to a different address.

---

## Phase 3 — Enable ERC-20 bridging (per rollup)

Deploys `ComposeL1Bridge` on L1, upgrades the portal to `ComposePortal`, and wires both sides.
Requires Phase 1 (shared infra) and the rollup migration (`just l1-migrate-v4`) to be complete.

All configuration is read from `config.json` via `ROLLUP_NAME` — no separate config file needed.

### 1. Ensure rollup section in config.json has L1 addresses filled in

```json
{
  "rollups": {
    "chain-100003": {
      "l1": {
        "portalProxy": "0x...",
        "proxyAdmin": "0x...",
        "proxyAdminOwner": "0x...",
        "systemConfig": "0x...",
        "l1CrossDomainMessenger": "0x..."
      }
    }
  }
}
```

### 2. Set .env

```
ROLLUP_OWNER_KEY=0x<rollup-proxy-admin-owner-private-key>
PROXY_ADMIN_OWNER_KEY=0x<compose-proxy-admin-owner-private-key>
RPC_URL=https://<l1-rpc>
```

### 3. Run the upgrade

```sh
just l1-upgrade-compose-bridge chain-100003 true   # dry run first
just l1-upgrade-compose-bridge chain-100003        # live
```

The script broadcasts as two addresses (`rollupAdminOwner` and `composeAdminOwner`), reading both
keys from `.env`.

**Important for multi-rollup clusters:** run rollups in sequence, not in parallel. The first rollup
deploys `ComposeERC20Lockbox` and saves its address to `config.json` under
`l1.deployed.erc20LockboxProxy`. Subsequent rollups read that address and reuse the same lockbox
automatically — no manual copy step required.

### 4. Wire L1 and L2 bridges

```sh
just l1-wire-bridges chain-100003
just l2-wire-bridge chain-100003
```

---

## Full deploy sequence

```sh
# Phase 1 — L1 shared infra (once per cluster)
# Fill l1.* fields in config.json, set PROXY_ADMIN_OWNER_KEY + GUARDIAN_KEY + RPC_URL (L1)
just l1-deploy-shared

# Phase 2 — L2 bridge (once per rollup)
# Add rollup section to config.json, set DEPLOYER_KEY + RPC_URL (L2)
just l2-deploy-bridge chain-100003
just l2-deploy-bridge chain-200005

# Phase 3 — ERC-20 bridging (once per rollup, after l1-migrate-v4)
# Set ROLLUP_OWNER_KEY + PROXY_ADMIN_OWNER_KEY + RPC_URL (L1)
just l1-upgrade-compose-bridge chain-100003   # deploys ComposeERC20Lockbox, saves to config.json
just l1-upgrade-compose-bridge chain-200005   # reuses lockbox from config.json automatically

# Wire bridges
just l1-wire-bridges chain-100003
just l1-wire-bridges chain-200005
just l2-wire-bridge chain-100003              # set RPC_URL to L2 first
just l2-wire-bridge chain-200005

```

---

## Verification

### L1 shared infra

```sh
# Confirm ProxyAdmin owner
cast call <PROXY_ADMIN> "owner()(address)" --rpc-url $RPC_URL

# Confirm guardian
cast call <SUPERCHAIN_CONFIG> "guardian()(address)" --rpc-url $RPC_URL

# Confirm ComposeDisputeGame registered at game type 5555
cast call <DISPUTE_GAME_FACTORY> "gameImpls(uint32)(address)" 5555 --rpc-url $RPC_URL
```

### L2 bridge

```sh
# Confirm L2 bridge wired to L1 counterpart
cast call <L2_COMPOSE_BRIDGE> "otherBridge()(address)" --rpc-url $L2_RPC_URL

# Confirm factory authorized bridges
cast call <CET_FACTORY> "authorizedBridges(address)(bool)" <L2_COMPOSE_BRIDGE> --rpc-url $L2_RPC_URL
cast call <CET_FACTORY> "authorizedBridges(address)(bool)" <L2L2_BRIDGE> --rpc-url $L2_RPC_URL
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Guardian not set` | `guardian` missing in `config.json` `l1.*` | Add `guardian` address |
| `Aggregation vkey not set` | `aggregationVkey` missing or zero | Add correct SP1 vkey |
| `L2Bridge.otherBridge mismatch` | `otherBridge` already set to a different address | Check which L1 bridge was used at deploy time |
| CREATE2 address collision | `create2Salt` differs from other rollups in cluster | Use the same `create2Salt` across all rollups |
| Wrong chain on L2 deploy | `RPC_URL` still pointing at L1 | Update `RPC_URL` in `.env` to the L2 RPC before running `l2-deploy-bridge` |
