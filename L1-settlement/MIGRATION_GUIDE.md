# Rollup Migration Guide: V3 vs V4

This guide explains how to migrate OP Stack rollups to use Compose shared infrastructure.

## Quick Start

### Detect Your Rollup Version

Your rollup's version determines which migration path to use:

```bash
# Check OptimismPortal version on-chain
cast call <PORTAL_ADDRESS> "version()(string)" --rpc-url <RPC_URL>
```

**Migration Path:**
- **V3 (3.x.x)**: Use `migrate-v3-rollup` → Full migration with contract upgrades
- **V4/V5 (any variant)**: Use `migrate-v4-rollup` → **Automatically handles portal upgrade if needed**

### Automatic Portal Detection

The V4 migration script **automatically detects** if your portal needs upgrading:

**Step 0: Portal Type Detection**
- ✅ If portal has `superRootsActive()` → Already OptimismPortalInterop → Skip upgrade
- ⚙️ If portal missing `superRootsActive()` → Standard Portal2 → **Auto-upgrade to OptimismPortalInterop**

**No manual intervention needed!** Just run `migrate-v4-rollup` and it handles everything.

---

## V3 Migration (V3 → V4 + Compose)

### Overview
Performs a **full migration** including:
- Deploy new V4 contract implementations
- Upgrade SystemConfig, OptimismPortal, and all bridges
- Enable ETH_LOCKBOX feature
- Migrate to Super Roots mode
- Transfer ETH to shared lockbox

### Steps Performed
1. Deploy V4 implementations (SystemConfig, Portal, XDM, Bridges)
2. Upgrade SystemConfig with l2ChainId and SuperchainConfig
3. Enable ETH_LOCKBOX feature flag
4. Upgrade OptimismPortal to OptimismPortalInterop
5. Authorize portal in shared lockbox
6. Upgrade all bridges (XDM, StandardBridge, ERC721Bridge)
7. Migrate to Super Roots + migrate ETH (atomic)

### Usage

```bash
# Dry-run (simulation)
just migrate-v3-rollup-dry <ROLLUP> <COMPOSE_NETWORK>

# Live migration
just migrate-v3-rollup <ROLLUP> <COMPOSE_NETWORK>
```

### Requirements
- `MIGRATION_PROXY_ADMIN_OWNER_KEY`: Rollup ProxyAdmin owner private key
- `COMPOSE_PROXY_ADMIN_OWNER_KEY`: Compose ProxyAdmin owner private key (for step 6)
- Rollup must be on V3 (version 3.x.x)

### Example

```bash
# Check version first
cast call 0xYourPortalAddress "version()(string)" --rpc-url $RPC_URL
# Returns: "3.10.0" → Use V3 migration

# Simulate
just migrate-v3-rollup-dry my-rollup-stage hoodi-stage

# Execute
just migrate-v3-rollup my-rollup-stage hoodi-stage
```

---

## V4 Migration (V4/V5 → Compose)

### Overview
Performs a **minimal migration** with automatic portal upgrade if needed.

**Key Feature:** Automatically upgrades standard Portal2 to PortalInterop in-flight!

### Steps Performed
0. **Auto-detect portal type** and upgrade to OptimismPortalInterop if needed (idempotent)
1. Enable ETH_LOCKBOX feature (if not already enabled)
2. Authorize portal in shared lockbox (if not already authorized)
3. Migrate to Super Roots + migrate ETH (atomic, if not already migrated)

### Usage

```bash
# Dry-run (simulation)
just migrate-v4-rollup-dry <ROLLUP> <COMPOSE_NETWORK>

# Live migration
just migrate-v4-rollup <ROLLUP> <COMPOSE_NETWORK>
```

### Requirements
- `MIGRATION_PROXY_ADMIN_OWNER_KEY`: Rollup ProxyAdmin owner private key
- `COMPOSE_PROXY_ADMIN_OWNER_KEY`: Compose ProxyAdmin owner private key
- Rollup must be on V4 or V5 (version 4.x.x or 5.x.x)

### Example

```bash
# Check version first
cast call 0xYourPortalAddress "version()(string)" --rpc-url $RPC_URL
# Returns: "5.0.0" → Use V4 migration

# Simulate
just migrate-v4-rollup-dry my-rollup-stage hoodi-stage

# Execute
just migrate-v4-rollup my-rollup-stage hoodi-stage
```

---

## Comparison: V3 vs V4

| Aspect | V3 Migration | V4 Migration |
|--------|--------------|--------------|
| **Contract Upgrades** | ✅ Yes (5 implementations) | ❌ No |
| **Steps** | 7 steps | 3 steps |
| **Duration** | ~5-10 minutes | ~1-2 minutes |
| **Gas Cost** | High (~5-10M gas) | Low (~500k gas) |
| **Risk Level** | Higher (upgrades) | Lower (state updates) |
| **Idempotent** | No | Yes (skips completed steps) |
| **Keys Required** | 2 (rollup + compose owner) | 2 (rollup + compose owner) |

---

## Pre-Migration Checklist

### For Both V3 and V4

- [ ] Rollup configuration file exists: `script/config/rollups/<ROLLUP>.json`
- [ ] Compose deployment exists: `script/config/compose/<COMPOSE_NETWORK>.json`
- [ ] Private keys configured in `.env`:
  - `MIGRATION_PROXY_ADMIN_OWNER_KEY`
  - `COMPOSE_PROXY_ADMIN_OWNER_KEY`
- [ ] RPC URL accessible
- [ ] Portal version checked and correct migration script selected

### V3 Specific
- [ ] Rollup is on V3 (version 3.x.x)
- [ ] No pending upgrades or migrations
- [ ] Sufficient ETH for gas (~0.1 ETH)

### V4 Specific
- [ ] Rollup is on V4/V5 (version 4.x.x or 5.x.x)
- [ ] SystemConfig supports ETH_LOCKBOX feature
- [ ] Sufficient ETH for gas (~0.02 ETH for portal upgrade + migration)
- [ ] Note: Portal will be auto-upgraded to OptimismPortalInterop if needed

---

## Version Detection

The migration scripts automatically detect your rollup version **before execution** using `cast`:

```bash
# Bash script checks version upfront (fail-fast)
PORTAL_VERSION=$(cast call $PORTAL_ADDRESS "version()(string)" --rpc-url $RPC_URL)
MAJOR_VERSION=$(echo "$PORTAL_VERSION" | cut -d'.' -f1)

# V3 script rejects V4/V5
if [ "$MAJOR_VERSION" -ge 4 ]; then
    echo "Error: Use migrate-v4-rollup for V4/V5 contracts"
    exit 1
fi

# V4 script rejects V3
if [ "$MAJOR_VERSION" -lt 4 ]; then
    echo "Error: Use migrate-v3-rollup for V3 contracts"
    exit 1
fi
```

**Version → Migration Path:**
- `"3.x.x"` → Use `migrate-v3-rollup`
- `"4.x.x"` → Use `migrate-v4-rollup`
- `"5.x.x"` → Use `migrate-v4-rollup`

**Benefits of upfront detection:**
- ✅ Fails immediately (before Forge compilation)
- ✅ Clear error messages with correct command suggestions
- ✅ Saves time and gas on incorrect migrations

---

## Post-Migration Validation

Both migration scripts perform automatic validation:

### Checks Performed
- ✅ ETH_LOCKBOX feature enabled
- ✅ Portal ASR points to Compose ASR
- ✅ Portal ethLockbox points to Compose lockbox
- ✅ superRootsActive = true
- ✅ Portal ETH balance = 0 (migrated to lockbox)
- ✅ Portal authorized in lockbox

---

## Troubleshooting

### "Error: This rollup is already on V4/V5"
**Cause:** You're trying to use V3 migration on a V4/V5 rollup.  
**Fix:** Use `migrate-v4-rollup` instead (detected before Forge runs).

### "Error: This rollup is on V3"
**Cause:** You're trying to use V4 migration on a V3 rollup.  
**Fix:** Use `migrate-v3-rollup` to perform the full upgrade (detected before Forge runs).

### "Could not detect portal version"
**Cause:** RPC connection issue or incorrect portal address.  
**Fix:** Verify portal address in rollup config and RPC accessibility.

### "SystemConfig doesn't support ETH_LOCKBOX feature"
**Cause:** Your rollup needs to be upgraded to V4 first.  
**Fix:** Use `migrate-v3-rollup` to perform the full upgrade.

### "MIGRATION_PROXY_ADMIN_OWNER_KEY not set"
**Cause:** Missing private key in `.env`.  
**Fix:** Add the rollup ProxyAdmin owner key to `.env`.

### "Portal already in Super Roots mode - skipping"
**Cause:** Migration already completed.  
**Fix:** This is expected for idempotent V4 migrations. No action needed.

---

## Advanced: Fork Testing

Test migrations on a local fork before executing on mainnet:

### V3 Fork Testing

```bash
# Test V3 migration on a forked network
just migrate-v3-fork <ROLLUP> <COMPOSE_NETWORK> <BLOCK_NUMBER>

# Example
just migrate-v3-fork my-rollup-stage sepolia-stage 9000000
```

**What it does:**
- Forks the network at specified block
- Impersonates rollup ProxyAdmin owner
- Executes full V3 migration (upgrades + Compose integration)
- Saves migration data to `deployments/rollups/fork/<ROLLUP>.json`

### V4 Fork Testing

```bash
# Test V4 migration on a forked network
just migrate-v4-fork <ROLLUP> <COMPOSE_NETWORK> <BLOCK_NUMBER>

# Example
just migrate-v4-fork unichain-stage sepolia-stage 9562313
```

**What it does:**
- Forks the network at specified block
- Impersonates both rollup and Compose ProxyAdmin owners
- Executes V4 migration (portal upgrade if needed + Compose integration)
- Tests all state transitions without saving separate files

### Use Cases

**Fork testing is recommended for:**
- Testing migrations before live execution
- Debugging migration issues
- Validating gas costs
- Verifying contract state changes

---

## Configuration Files

### Rollup Configuration (`script/config/rollups/<ROLLUP>.json`)

```json
{
  "l2ChainId": 901,
  "proxyAdmin": {
    "impl": "0x...",
    "owner": "0x..."
  },
  "l1SystemConfigAddress": "0x...",
  "optimismPortal": {
    "impl": "0x...",
    "proxy": "0x..."
  },
  "l1CrossDomainMessenger": "0x...",
  "l1StandardBridge": "0x...",
  "l1ERC721Bridge": "0x..."
}
```

### Compose Configuration (`script/config/compose/<NETWORK>.json`)

```json
{
  "l1ChainId": 17000,
  "l1Name": "holesky",
  "proxyAdminOwner": "0x...",
  "superchainConfig": "0x...",
  "disputeGameFactory": "0x...",
  "anchorStateRegistry": "0x...",
  "ethLockbox": "0x..."
}
```

---

## File Structure

```
script/migrate/
├── MigrateRollupV3.s.sol      # V3→V4 full migration
├── MigrateRollupV3IO.sol      # V3 input/output
├── MigrateRollupV4.s.sol      # V4→Compose minimal migration
└── MigrateRollupV4IO.sol      # V4 input/output

scripts/
├── migrate-v3-rollup.sh       # V3 migration script
└── migrate-v4-rollup.sh       # V4 migration script
```

---

## Summary

**Use V3 migration (`migrate-v3-rollup`) if:**
- Your rollup is on V3 (version 3.x.x)
- You need a full upgrade to V4 + Compose

**Use V4 migration (`migrate-v4-rollup`) if:**
- Your rollup is already on V4/V5 (version 4.x.x or 5.x.x)
- You only need to connect to Compose infrastructure

