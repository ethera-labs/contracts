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
SAVE_DEPLOY_OUTPUT=true just l1-deploy-shared
```

`SAVE_DEPLOY_OUTPUT=true` writes the deployed addresses back into `config.json` under `l1.deployed`
automatically. After a successful run, `config.json` will have:

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
      "composeDisputeGame": "0x..."
    }
  }
}
```

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
      "rpcUrl": "https://...",
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
| `rpcUrl` | Informational only — scripts use `$RPC_URL` from `.env`, not this field |

### 2. Set .env

```
ROLLUP_NAME=chain-100003
DEPLOYER_KEY=0x<deployer-private-key>
RPC_URL=https://<l2-rpc>
```

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

### 1. Create the upgrade config file

Create a JSON file (e.g. `upgrade-compose-bridge-chain-100003.json`). Keys **must** be in alphabetical order:

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
| `erc20LockboxProxy` | Zero address to deploy a new `ComposeERC20Lockbox`; or pass an existing proxy |
| `l1Xdm` | `rollups.<name>.l1.l1CrossDomainMessenger` in `config.json` |
| `portalProxy` | `rollups.<name>.l1.portalProxy` in `config.json` |
| `rollupAdminOwner` | `rollups.<name>.l1.proxyAdminOwner` in `config.json` |
| `rollupProxyAdmin` | `rollups.<name>.l1.proxyAdmin` in `config.json` |
| `superchainConfig` | `l1.deployed.superchainConfig` in `config.json` |
| `systemConfig` | `rollups.<name>.l1.systemConfig` in `config.json` |

### 2. Run the upgrade

```sh
just l1-upgrade-compose-bridge upgrade-compose-bridge-chain-100003.json true   # dry run
just l1-upgrade-compose-bridge upgrade-compose-bridge-chain-100003.json        # live
```

This script broadcasts as two addresses (`rollupAdminOwner` and `composeAdminOwner`). Both
private keys must be available. Pass them with `--private-key` if running forge directly:

```sh
forge script script/l1/deploy/UpgradeToComposeBridge.s.sol --sig "run(string,bool)" upgrade-compose-bridge-chain-100003.json false --private-key $ROLLUP_OWNER_KEY --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC_URL --broadcast --slow
```

The script prints the deployed `ComposeL1Bridge` proxy address on completion.

### 3. Wire L1 and L2 bridges

Set in `.env`:

```
L1_COMPOSE_BRIDGE=0x<ComposeL1Bridge proxy from step 2>
L2_COMPOSE_BRIDGE=0x<L2ComposeBridge from just l2-deploy-bridge>
COMPOSE_PORTAL=0x<portalProxy>
COMPOSE_ETH_LOCKBOX=0x<l1.deployed.ethLockbox>
```

Then wire the L1 side:

```sh
just l1-wire-bridges
```

And the L2 side (if not already wired during `just l2-deploy-bridge`):

```sh
just l2-wire-bridge chain-100003
```

---

## Full deploy sequence

```sh
# Phase 1 — L1 shared infra (once per cluster)
# Fill l1.* fields in config.json, set PROXY_ADMIN_OWNER_KEY + GUARDIAN_KEY + RPC_URL
just l1-deploy-shared

# Phase 2 — L2 bridge (once per rollup)
# Add rollup section to config.json, set ROLLUP_NAME + DEPLOYER_KEY + RPC_URL
just l2-deploy-bridge chain-100003

# Wire L2 bridge to L1 (if L1_COMPOSE_BRIDGE was not set above)
# Set L2_COMPOSE_BRIDGE + L1_COMPOSE_BRIDGE in .env
just l2-wire-bridge chain-100003

# Phase 3 — ERC-20 bridging (once per rollup, after l1-migrate-v4)
# Create upgrade-compose-bridge-chain-100003.json (see Phase 3 above)
just l1-upgrade-compose-bridge upgrade-compose-bridge-chain-100003.json
# Set L1_COMPOSE_BRIDGE + L2_COMPOSE_BRIDGE + COMPOSE_PORTAL + COMPOSE_ETH_LOCKBOX in .env
just l1-wire-bridges

# Optional: deploy DEX tokens
just l2-deploy-weth chain-100003
just l2-deploy-dex-tokens chain-100003
# Or all at once:
just l2-deploy-all chain-100003
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
| `SAVE_DEPLOY_OUTPUT` not set | Deployed addresses not written to config.json | Re-run with `SAVE_DEPLOY_OUTPUT=true` prefix |
