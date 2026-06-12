<p align="center"><img src="https://framerusercontent.com/images/9FedKxMYLZKR9fxBCYj90z78.png?scale-down-to=512&width=893&height=363" alt="SSV Network"></p>

<a href="https://discord.com/invite/ssvnetworkofficial"><img src="https://img.shields.io/badge/discord-%23ssvlabs-8A2BE2.svg" alt="Discord" /></a>

# Compose Network Contracts

> ⚠️ **HEAVY DEVELOPMENT — NOT AUDITED — NOT PRODUCTION READY**

Smart contracts for the Compose Network: a shared settlement layer that lets multiple OP Stack rollups share a single dispute game, ETH lockbox, and anchor state registry on L1, plus cross-rollup bridging and DEX contracts on L2.

---

## Repository Structure

```
contracts/
├── src/
│   ├── l1/            # ComposeDisputeGame, ComposeAnchorStateRegistry, lockboxes, whitelist, portals
│   └── l2/            # CETFactory, L2ComposeBridge, ComposeETHLiquidity, ComposeL2ToL2Bridge
├── test/
│   ├── l1/            # L1 contract tests + setup harness
│   └── l2/            # L2 contract tests
├── script/
│   ├── l1/
│   │   ├── deploy/    # DeploySharedInfra
│   │   ├── migrate/   # MigrateRollup*, whitelist-aware portal upgrades
│   │   └── libraries/ # ComposeConfig (reads config.json)
│   └── l2/
│       ├── bridge/    # DeployComposeBridge, WireL2ComposeBridge
│       └── libraries/ # RollupConfig (reads config.json)
├── lib/               # Foundry dependencies (submodules)
├── config.json        # All config: shared L1 infra + per-rollup addresses
├── foundry.toml
└── justfile           # All deployment commands
```

---

## Configuration

All scripts read from a single `config.json`. Private keys always come from the environment, never from config files.

### `config.json`

```json
{
  "l1": {
    "guardian": "0x...",
    "proxyAdminOwner": "0x...",
    "depositWhitelistDefaultAdmin": "0x...",
    "depositWhitelistAdmin": "0x...",
    "authorizedProposer": "0x...",
    "sp1Verifier": "0x...",
    "aggregationVkey": "0x...",
    "proofMaturityDelaySeconds": 0,
    "disputeGameFinalityDelaySeconds": 0,
    "disputeGameInitBond": "80000000000000000",
    "deployed": {
      "l1ChainId": 0,
      "proxyAdmin": "0x...",
      "superchainConfig": "0x...",
      "disputeGameFactory": "0x...",
      "anchorStateRegistry": "0x...",
      "ethLockbox": "0x...",
      "depositWhitelist": "0x...",
      "composeDisputeGame": "0x...",
      "erc20LockboxProxy": "0x..."
    }
  },
  "rollups": {
    "chain-100003": {
      "chainId": "100003",
      "rpcUrl": "https://...",
      "owner": "0x...",
      "coordinator": "0x...",
      "l1ChainId": "11155111",
      "l2Xdm": "0x4200000000000000000000000000000000000007",
      "create2Salt": "0x...",
      "initialEthSeed": "0",
      "l1": {
        "portalProxy": "0x...",
        "portalImpl": "0x...",
        "proxyAdmin": "0x...",
        "proxyAdminOwner": "0x...",
        "systemConfig": "0x...",
        "l1CrossDomainMessenger": "0x...",
        "l1StandardBridge": "0x...",
        "l1ERC721Bridge": "0x...",
        "composeBridge": "0x..."
      }
    }
  }
}
```

**`l1`** — shared infrastructure config. Static fields are filled manually before deploy. `deployed.*` fields are written automatically by `just l1-deploy-shared` when `SAVE_DEPLOY_OUTPUT=true`.

`depositWhitelistDefaultAdmin` receives `DEFAULT_ADMIN_ROLE` on `L1DepositWhitelist` and is used only to grant/revoke roles. `depositWhitelistAdmin` receives `DEPOSIT_WHITELIST_ROLE` and can allow/block portal and ERC-20 deposit paths. These may be the same multisig for MVP, but the roles are separate.

**`rollups`** — one section per rollup. `l1.*` fields are the existing OP Stack contracts on L1 that the migration scripts will upgrade.

### `.env`

Copy `.env.example` and fill in private keys:

```sh
cp .env.example .env
```

```
PROXY_ADMIN_OWNER_KEY=0x...
GUARDIAN_KEY=0x...
DEPOSIT_WHITELIST_ADMIN_KEY=0x...

ROLLUP_NAME=chain-100003
DEPLOYER_KEY=0x...
RPC_URL=https://...
```

---

## Guides

- [Migrate an existing rollup to Compose](docs/guides/migrate-rollup.md) — V3 and V4 migration paths, step-by-step
- [Deploy Compose bridge](docs/guides/deploy-compose-bridge.md) — L1 shared infra + L2 bridge per rollup

---

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [just](https://github.com/casey/just#installation)

### Install

```sh
git submodule update --init --recursive
forge build
```

### Test

```sh
just test
```

### L1 Deployment (new compose network)

```sh
# 1. Fill in l1.* fields in config.json (guardian, verifier, keys, delays)
# 2. Set PROXY_ADMIN_OWNER_KEY + GUARDIAN_KEY + RPC_URL in .env

SAVE_DEPLOY_OUTPUT=true just l1-deploy-shared
# ^ writes deployed addresses back into config.json l1.deployed automatically
```

### L1 Migration (existing OP Stack rollup)

> **Prerequisite:** `l1.deployed.*` in `config.json` must be filled in (run `just l1-deploy-shared` first, or obtain the cluster operator's `config.json`).

```sh
# 1. Add your rollup under rollups in config.json with l1.* addresses
# 2. Set ROLLUP_NAME + ROLLUP_OWNER_KEY + PROXY_ADMIN_OWNER_KEY + RPC_URL in .env

just l1-migrate-v4 chain-100003        # live
just l1-migrate-v4 chain-100003 true   # dry run
just l1-migrate-v3 chain-100003        # V3 rollup (full upgrade)
```

After a whitelist-aware portal upgrade, all new L1 deposits are default-denied until the whitelist role holder explicitly allows the portal path and any ERC-20 tokens:

```sh
just l1-whitelist-portal chain-100003 true
just l1-whitelist-erc20 chain-100003 0x<Token> true
```

The upgrade also disables legacy `L1StandardBridge` deposit entry points. Existing completed deposits remain historical state; new deposits must use the Compose paths and pass the whitelist.

### L2 Deployment

```sh
# 1. Add rollup section to config.json with owner, coordinator, l2Xdm, etc.
# 2. Set ROLLUP_NAME + DEPLOYER_KEY + RPC_URL in .env

just l2-deploy-bridge chain-100003
```

---

## Architecture

```
L1 (Ethereum / Sepolia)
│
│  ┌─────────────────────────────────────────────────────────┐
│  │  Compose Shared Infrastructure (one per cluster)        │
│  │                                                         │
│  │  SuperchainConfig ──── guardian, pause                  │
│  │  DisputeGameFactory ── registers ComposeDisputeGame     │
│  │  ComposeAnchorStateRegistry ── superblock anchors       │
│  │  ComposeETHLockbox ── unified ETH liquidity             │
│  │  L1DepositWhitelist ── default-deny deposit policy       │
│  └─────────────────────────────────────────────────────────┘
│            ↑ each rollup's portal authorizes into lockbox
│
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  │  Rollup A   │  │  Rollup B   │  │  Rollup N   │
│  │  Portal     │  │  Portal     │  │  Portal     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
│         │                │                │
└─────────┴────────────────┴────────────────┘

L2 (each rollup)
│
│  ┌────────────────────────────────────────────────┐
│  │  Cross-rollup bridge stack (CREATE2, same addr) │
│  │  CetFactory, UniversalBridgeMailbox             │
│  │  ComposeETHLiquidity, ComposeL2ToL2Bridge       │
│  └────────────────────────────────────────────────┘
│
│  ┌─────────────────────────────┐
│  │  Per-rollup                 │
│  │  L2ComposeBridge            │
│  └─────────────────────────────┘
```

---

## Available `just` Recipes

```sh
just          # list all recipes
just build
just test
just clean
just fmt

# L1
just l1-deploy-shared
just l1-migrate-v3 <rollup> [dryRun]
just l1-migrate-v4 <rollup> [dryRun]
just l1-upgrade-portal-interop <rollup> [dryRun]
just l1-upgrade-compose-portal <rollup> <proofMaturityDelay> [dryRun]
just l1-upgrade-compose-bridge <rollup> [dryRun]
just l1-wire-bridges <rollup>
just l1-whitelist-portal <rollup> <allowed>
just l1-whitelist-erc20 <rollup> <token> <allowed>

# L2
just l2-deploy-bridge [rollup]
just l2-deploy-l2l2-bridge [rollup]
just l2-wire-bridge [rollup]
```

---

## Links

- [Optimism Bedrock](https://github.com/ethereum-optimism/optimism)
- [SP1 Documentation](https://docs.succinct.xyz/)
- [Foundry Book](https://book.getfoundry.sh/)

## License

**GNU General Public License v3.0 or later (GPL-3.0-or-later)**. See [LICENSE](LICENSE).

Third-party dependencies: see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
