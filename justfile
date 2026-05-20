set dotenv-load

# ============================================================
# Shared
# ============================================================

default:
    @just --list

build:
    forge build

test:
    forge test

clean:
    forge clean

fmt:
    forge fmt

# ============================================================
# L1  (reads config.json — fill in l1.* fields first)
# ============================================================

l1-deploy-shared:
    SAVE_DEPLOY_OUTPUT=true forge script script/l1/deploy/DeploySharedInfra.s.sol --tc DeploySharedInfra --rpc-url $RPC_URL --broadcast --slow

# rollup = key under rollups in config.json (e.g. rollupA, rollupB)
l1-migrate-v3 rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/MigrateRollupV3.s.sol --tc MigrateRollupV3 --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-migrate-v4 rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/MigrateRollupV4.s.sol --tc MigrateRollupV4 --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-upgrade-portal-interop rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/UpgradeToPortalInterop.s.sol --tc UpgradeToPortalInterop --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-upgrade-compose-portal rollup proofMaturityDelay dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/UpgradeComposePortal.s.sol --tc UpgradeComposePortal --sig "run(uint256,bool)" {{proofMaturityDelay}} {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

# Requires ROLLUP_OWNER_KEY and PROXY_ADMIN_OWNER_KEY in .env (broadcasts as two addresses)
l1-upgrade-compose-bridge rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/deploy/UpgradeToComposeBridge.s.sol --tc UpgradeToComposeBridge --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-upgrade-bridge-impl rollup:
    ROLLUP_NAME={{rollup}} forge script script/l1/deploy/UpgradeL1BridgeImpl.s.sol --tc UpgradeL1BridgeImpl --rpc-url $RPC_URL --broadcast --slow

# rollup = key under rollups in config.json (e.g. rollupA, rollupB)
l1-wire-bridges rollup:
    ROLLUP_NAME={{rollup}} forge script script/l1/deploy/WireComposeBridges.s.sol --tc WireComposeBridges --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# L2 bridge  (reads config.json via ROLLUP_NAME)
# ============================================================

l2-deploy-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/DeployComposeBridge.s.sol --tc DeployComposeBridge --rpc-url $RPC_URL --broadcast --slow

l2-deploy-l2l2-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/DeployAndWireComposeBridge.s.sol --tc DeployAndWireComposeBridge --rpc-url $RPC_URL --broadcast --slow

l2-wire-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/WireL2ComposeBridge.s.sol --tc WireL2ComposeBridge --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# Fork runner  (spins up anvil fork, runs recipe, tears down)
# ============================================================

# Usage: just fork <recipe> [args...]
# Example: just fork l1-migrate-v3 rollupA
fork +args:
    #!/usr/bin/env bash
    anvil --fork-url $RPC_URL --port 8545 &
    ANVIL_PID=$!
    trap "kill $ANVIL_PID 2>/dev/null" EXIT
    sleep 2
    RPC_URL=http://localhost:8545 just {{args}}
