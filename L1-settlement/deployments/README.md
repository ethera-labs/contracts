# Deployment Output Structure

This directory contains structured deployment outputs for Compose infrastructure and rollup migrations.

## Directory Structure

```
deployments/
├── compose/                    # Compose shared infrastructure
│   ├── hoodi-stage.json       # Deployment per network-environment
│   └── hoodi-prod.json
│
└── rollups/                    # Rollup migrations
    ├── rollup-a-stage.json    # Regular migrations
    ├── rollup-b-prod.json
    │
    └── fork/                   # Fork migrations (testing)
        ├── rollup-a-stage.json
        └── rollup-b-stage.json
```

## Quick Reference

### Compose Infrastructure

**Deploy:**
```bash
just deploy-network hoodi-stage
```

**View:**
```bash
just show-deployments              # List all
just get-deployment hoodi-stage    # View specific
just validate-deployment hoodi-stage
```

**Output:** `deployments/compose/{NETWORK}.json`

### Rollup Migrations

**Migrate:**
```bash
# Regular migration (live)
just migrate-rollup rollup-a-stage hoodi-stage

# Fork migration (test)
just migrate-fork rollup-a-stage hoodi-stage 1234567

# Dry run (no output saved)
just migrate-rollup-dry rollup-a-stage hoodi-stage
```

**View:**
```bash
just show-migrations                    # List all
just get-migration rollup-a-stage      # Regular
just get-migration rollup-a-stage fork # Fork
just validate-migration rollup-a-stage
```

**Output:**
- Regular: `deployments/rollups/{ROLLUP}.json`
- Fork: `deployments/rollups/fork/{ROLLUP}.json`

## File Formats

### Compose Deployment
Contains Phase 1 shared infrastructure contracts:
- ProxyAdmin
- SuperchainConfig (proxy + impl)
- DisputeGameFactory (proxy + impl)
- AnchorStateRegistry (proxy + impl)
- ETHLockbox (proxy + impl)
- ComposeDisputeGame (impl)

Each includes: proxy/impl addresses, constructor args, initialize data, tx hashes, blocks.

### Rollup Migration
Contains Phase 2 upgraded contracts:
- SystemConfig (proxy + old impl + new impl)
- OptimismPortal (proxy + old impl + new impl)
- L1CrossDomainMessenger (proxy + old impl + new impl)
- L1StandardBridge (proxy + old impl + new impl)
- L1ERC721Bridge (proxy + old impl + new impl)

Each includes: proxy address, old/new impl addresses, constructor args, upgrade data, tx hashes, blocks.

## Documentation

- **Compose Deployments:** See existing documentation
- **Rollup Migrations:** See [docs/ROLLUP_MIGRATIONS.md](../docs/ROLLUP_MIGRATIONS.md)

## Version Control

- All deployment files are tracked in git for audit trail
- Fork migration files may be gitignored if preferred (for testing only)
- Each file is self-contained with complete deployment metadata
