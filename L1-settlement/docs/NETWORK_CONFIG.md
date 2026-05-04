# Network Configuration Guide

Complete reference for configuring L1 networks and rollup migrations.

## Overview

Compose uses two configuration systems:

1. **`networks.toml`** - L1 networks where shared infrastructure deploys (Phase 1)
2. **`script/config/rollups/*.json`** - Rollup-specific configs for migration (Phase 2)

---

## Part 1: L1 Network Configuration

### File: `networks.toml`

Located at project root, gitignored. Contains L1 network settings for deploying shared infrastructure.

### Complete Example

```toml
[networks.hoodi-stage]
# Connection
name = "Hoodi Stage"
rpc_url = "https://0xrpc.io/hoodi"
chain_id = 560048
explorer_url = "https://hoodscan.io"
explorer_api_url = "https://api.hoodscan.io/api"

# Phase 1: Shared Infrastructure Actors
guardian = "0x64F38Fe8EC155134DF973012ED8bb40f10D31F77"
proxy_admin_owner = "0x64F38Fe8EC155134DF973012ED8bb40f10D31F77"
authorized_proposer = "0xb054981b2Ef67603E50B1bD840D0834ef5bcceE4"
sp1_verifier = "0x17Ef331C3c90E9e5718e81085c721a404eF18436"
aggregation_vkey = "0x0059ae2f8c8ad61a6af02594067148b58dbecff2e3352170923efda8ea603f1e"

# Timing Parameters (seconds)
proof_maturity_delay_seconds = 604800      # 7 days
dispute_game_finality_delay_seconds = 302400  # 3.5 days

# Economic Parameters (wei)
dispute_game_init_bond = "80000000000000000"  # 0.08 ETH
```

### Parameter Reference

| Parameter | Type | Required | Description | Default |
|-----------|------|----------|-------------|---------|
| **Network Connection** |
| `name` | string | Yes | Display name | - |
| `rpc_url` | string | Yes | L1 RPC endpoint | - |
| `chain_id` | number | Yes | L1 chain ID | - |
| `explorer_url` | string | No | Block explorer URL | - |
| `explorer_api_url` | string | No | Explorer API for verification | - |
| **Shared Infrastructure** |
| `guardian` | address | Yes | Can pause cluster | - |
| `proxy_admin_owner` | address | Yes | Can upgrade proxies | - |
| `authorized_proposer` | address | Yes | Publishes superblocks | - |
| `sp1_verifier` | address | Yes | SP1 verifier contract | - |
| `aggregation_vkey` | bytes32 | Yes | SP1 aggregation vkey | - |
| **Timing** |
| `proof_maturity_delay_seconds` | uint256 | No | Withdrawal delay | 604800 (7d) |
| `dispute_game_finality_delay_seconds` | uint256 | No | Post-resolution delay | 302400 (3.5d) |
| **Economic** |
| `dispute_game_init_bond` | string | No | Game creation bond (wei) | "0" |

### Key Concepts

**Guardian:**
- Can pause the entire cluster via `SuperchainConfig`
- Should be a multisig on mainnet
- Has emergency stop power

**Proxy Admin Owner:**
- Controls all proxy upgrades
- Should be a multisig on mainnet
- Can upgrade all shared contracts

**Authorized Proposer:**
- Shared Publisher account that publishes superblocks
- Needs to sign and submit proofs
- Pays gas for superblock submissions

**SP1 Verifier:**
- Contract that verifies SP1 proofs
- Deploy once per network, reuse
- From SP1 contracts repo

**Aggregation Vkey:**
- 32-byte verification key from SP1 build
- Critical for proof verification

### Security Best Practices

**Mainnet:**
```toml
guardian = "0xMultisigAddress"           # 3-of-5 or higher
proxy_admin_owner = "0xMultisigAddress"  # Same or different
authorized_proposer = "0xSharedPubisher" # Automated system
```

**Testnet:**
```toml
guardian = "0xYourEOA"                   # Fine for testing
proxy_admin_owner = "0xYourEOA"          # Fine for testing
authorized_proposer = "0xYourEOA"        # Fine for testing
```

### Managing Networks

```bash
# List configured networks
just list-networks

# Validate config
just validate-config hoodi-stage

# Test connection
just test-network hoodi-stage
```

---

## Part 2: Rollup Configuration

### File: `script/config/rollups/<rollup-name>.json`

Per-rollup configuration for Phase 2 migration. Contains existing L1 contract addresses.

### Complete Example

```json
{
  "l2ChainId": 77777,
  "l1SystemConfigAddress": "0xdb356c4ed9a9ef4833eea2a8052668b05eafc7d7",
  "optimismPortal": {
    "proxy": "0xB8b340D118A807BA7E6abce111eb3816152072d1",
    "impl": "0xB443Da3e07052204A02d630a8933dAc05a0d6fB4"
  },
  "l1CrossDomainMessenger": "0xf705129966C71b94534a7E84bCc52edefe1e6706",
  "l1StandardBridge": "0xE6456C49bAe7FF20Bee0D01948d6d0F82dD821E9",
  "l1ERC721Bridge": "0xfc67ad4195E5c86A89676d8b0f3BfEe5150e5D6C",
  "proxyAdmin": {
    "impl": "0x3b0e5218B083d9e0e3fB1094b47ca7ec0515c313",
    "owner": "0xA139A1776E60F9645533a9AD419461818D6839a1"
  }
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `l2ChainId` | number | L2 chain ID of the rollup |
| `l1SystemConfigAddress` | address | SystemConfig proxy address |
| `optimismPortal.proxy` | address | OptimismPortal proxy address |
| `optimismPortal.impl` | address | Current OptimismPortal impl (for tracking) |
| `l1CrossDomainMessenger` | address | L1CrossDomainMessenger proxy |
| `l1StandardBridge` | address | L1StandardBridge proxy |
| `l1ERC721Bridge` | address | L1ERC721Bridge proxy |
| `proxyAdmin.impl` | address | ProxyAdmin address |
| `proxyAdmin.owner` | address | ProxyAdmin owner (must authorize migration) |

### How to Find Addresses

**From existing OP Stack deployment:**

```bash
# If you have the deployment artifacts
cat deployments/<network>/OptimismPortal.json | jq -r '.address'

# From block explorer (search for rollup's L1 contracts)

# From on-chain (if you know SystemConfig)
cast call $SYSTEM_CONFIG "optimismPortal()" --rpc-url $L1_RPC

# From Superchain Registry (for public OP Stack chains)
# https://github.com/ethereum-optimism/superchain-registry
```

### Creating Rollup Config

1. **Gather addresses** from your existing OP Stack deployment
2. **Create JSON file** at `script/config/rollups/<name>.json`
3. **Validate** the config exists and is readable

```bash
# Check file exists
ls -l script/config/rollups/your-rollup.json

# Validate JSON
jq . script/config/rollups/your-rollup.json

# Test migration (dry run)
just migrate-rollup-dry your-rollup hoodi-stage
```

### Naming Convention

Use descriptive names that match your rollup and environment:

```
script/config/rollups/
├── rollup-a-stage.json       # Rollup A on stage
├── rollup-a-prod.json        # Rollup A on production
├── rollup-b-stage.json       # Rollup B on stage
└── my-chain-testnet.json     # Custom naming
```

### Requirements

**For migration, you need:**
- ✅ Rollup must be OP Stack v3.x.x compatible
- ✅ ProxyAdmin owner must authorize migration transactions
- ✅ All proxy addresses must be correct
- ✅ Shared infrastructure must already be deployed on the L1

---

## Configuration Workflow

### Phase 1: Deploy Shared Infrastructure

1. Configure L1 network in `networks.toml`
2. Deploy: `just deploy-network hoodi-stage`
3. Save deployment addresses

### Phase 2: Migrate Rollups

1. Create rollup config in `script/config/rollups/`
2. Test on fork: `just migrate-fork rollup-a hoodi-stage 1234567`
3. Migrate live: `just migrate-rollup rollup-a hoodi-stage`

---

## Environment Variables (`.env`)

Private keys and API keys stay in `.env` (never committed):

```bash
# Required
PRIVATE_KEY=0x...
ETHERSCAN_API_KEY=...

# Optional (for fork testing)
FORK_RPC_URL=https://...
```

---

## Troubleshooting

### "Network not found in networks.toml"

Add the network configuration:
```bash
vim networks.toml
# Add [networks.your-network] section
```

### "Rollup config not found"

Create the rollup config file:
```bash
touch script/config/rollups/your-rollup.json
# Add JSON content
```

### "Guardian not set"

Set `guardian` in `networks.toml`:
```toml
[networks.hoodi-stage]
guardian = "0xYourAddress"
```

### "RPC connection failed"

Check `rpc_url` and ensure:
- URL is correct
- API key is valid (if using)
- Network is accessible
- Rate limits not exceeded

---

## Examples

### Mainnet Configuration

```toml
[networks.ethereum]
name = "Ethereum Mainnet"
rpc_url = "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
chain_id = 1
explorer_url = "https://etherscan.io"
explorer_api_url = "https://api.etherscan.io/api"

guardian = "0xMultisig5of9"
proxy_admin_owner = "0xMultisig5of9"
authorized_proposer = "0xAutomatedProposer"
sp1_verifier = "0xSP1VerifierMainnet"
aggregation_vkey = "0x..."

proof_maturity_delay_seconds = 604800
dispute_game_finality_delay_seconds = 302400
dispute_game_init_bond = "100000000000000000"  # 0.1 ETH
```

### Testnet Configuration

```toml
[networks.sepolia]
name = "Sepolia"
rpc_url = "https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"
chain_id = 11155111
explorer_url = "https://sepolia.etherscan.io"
explorer_api_url = "https://api-sepolia.etherscan.io/api"

guardian = "0xYourEOA"
proxy_admin_owner = "0xYourEOA"
authorized_proposer = "0xYourEOA"
sp1_verifier = "0xSP1VerifierSepolia"
aggregation_vkey = "0x01..."  # Test vkey

proof_maturity_delay_seconds = 3600      # 1 hour for faster testing
dispute_game_finality_delay_seconds = 1800  # 30 min
dispute_game_init_bond = "10000000000000000"  # 0.01 ETH
```

---

## Reference

- **Template:** `networks.toml.example`
- **Rollup Example:** `script/config/rollups/rollup-a-stage.json.example`
- **Commands:** Run `just` to see all available commands
- **Validation:** `just validate-config <network>`

---

**Next:** See [SHARED_INFRA.md](./SHARED_INFRA.md) for deployment details.
