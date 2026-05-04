#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ROLLUP=$1
COMPOSE_NETWORK=$2
DRY_RUN=${3:-false}

# Check if rollup and compose network parameters are provided
if [ -z "$ROLLUP" ] || [ -z "$COMPOSE_NETWORK" ]; then
    echo -e "${RED}Error: Both rollup and compose network parameters required${NC}"
    echo "Usage: $0 <rollup> <compose_network> [dry-run]"
    echo "Example: $0 rollup-a-stage hoodi-stage"
    echo "Example: $0 rollup-a-prod hoodi-prod dry-run"
    exit 1
fi

# Check if rollup config exists
ROLLUP_CONFIG="script/config/rollups/${ROLLUP}.json"
if [ ! -f "$ROLLUP_CONFIG" ]; then
    echo -e "${RED}Error: Rollup configuration not found: $ROLLUP_CONFIG${NC}"
    exit 1
fi

# Check if compose config exists
COMPOSE_CONFIG="script/config/compose/${COMPOSE_NETWORK}.json"
if [ ! -f "$COMPOSE_CONFIG" ]; then
    echo -e "${RED}Error: Compose configuration not found: $COMPOSE_CONFIG${NC}"
    exit 1
fi

# Check for ETHERSCAN_API_KEY (warn but don't fail)
if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
    echo -e "${YELLOW}Warning: ETHERSCAN_API_KEY not set in .env. Verification will be skipped.${NC}"
fi

# Check for MIGRATION_PROXY_ADMIN_OWNER_KEY (required for live mode)
if [ "$DRY_RUN" != "dry-run" ]; then
    if [ -z "${MIGRATION_PROXY_ADMIN_OWNER_KEY:-}" ]; then
        echo -e "${RED}Error: MIGRATION_PROXY_ADMIN_OWNER_KEY not set in .env${NC}"
        echo "This private key is required to execute the migration (Steps 2-4, 8-9)."
        echo "Add it to your .env file with the Rollup ProxyAdmin owner private key."
        exit 1
    fi
    
    # Warn if COMPOSE_PROXY_ADMIN_OWNER_KEY is not set (needed for Step 6)
    if [ -z "${COMPOSE_PROXY_ADMIN_OWNER_KEY:-}" ]; then
        echo -e "${YELLOW}Warning: COMPOSE_PROXY_ADMIN_OWNER_KEY not set in .env${NC}"
        echo "This key is needed for Step 6 (authorize portal in lockbox)."
        echo "If not set, MIGRATION_PROXY_ADMIN_OWNER_KEY will be used as fallback."
        echo "Set COMPOSE_PROXY_ADMIN_OWNER_KEY if the Compose ProxyAdmin has a different owner."
    fi
fi

# Convert dry-run flag to boolean
IS_DRY_RUN="false"
if [ "$DRY_RUN" = "dry-run" ]; then
    IS_DRY_RUN="true"
fi

echo -e "${GREEN}Migration configuration:${NC}"
echo "  Rollup: $ROLLUP (from $ROLLUP_CONFIG)"
echo "  Compose Network: $COMPOSE_NETWORK (from $COMPOSE_CONFIG)"
echo "  Mode: $([ "$IS_DRY_RUN" = "true" ] && echo "DRY RUN (simulation only)" || echo "LIVE (will broadcast transactions)")"

# Load network configuration
# Set a dummy DEPLOYER_PRIVATE_KEY if not present (migrations use MIGRATION_PROXY_ADMIN_OWNER_KEY instead)
if [ -z "${DEPLOYER_PRIVATE_KEY:-}" ]; then
    export DEPLOYER_PRIVATE_KEY="0x0000000000000000000000000000000000000000000000000000000000000001"
fi

source scripts/parse-network.sh "$COMPOSE_NETWORK"

CHAIN_ID=$(jq -r '.l2ChainId' "$ROLLUP_CONFIG")
PORTAL_ADDRESS=$(jq -r '.optimismPortal.proxy' "$ROLLUP_CONFIG")

echo "Rollup:       $ROLLUP"
echo "Compose Net:  $NETWORK_NAME"
echo "L2 Chain ID:  $CHAIN_ID"
echo "RPC URL:      $NETWORK_RPC_URL"
echo ""

# Detect portal version to ensure we're using the correct migration script
echo "Detecting OptimismPortal version..."
PORTAL_VERSION=$(cast call "$PORTAL_ADDRESS" "version()(string)" --rpc-url "$NETWORK_RPC_URL" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not detect portal version${NC}"
    echo "Make sure the portal address is correct and the RPC is accessible."
    echo "Portal address: $PORTAL_ADDRESS"
    exit 1
fi

echo "  Portal version: $PORTAL_VERSION"

# Strip quotes and extract major version (e.g., "3.10.0" -> 3)
PORTAL_VERSION_CLEAN=$(echo "$PORTAL_VERSION" | tr -d '"')
MAJOR_VERSION=$(echo "$PORTAL_VERSION_CLEAN" | cut -d'.' -f1)

# V3 migration requires version 3.x.x
if [ "$MAJOR_VERSION" -ge 4 ]; then
    echo -e "${RED}Error: This rollup is already on V4/V5 (version $PORTAL_VERSION)${NC}"
    echo ""
    echo "Use the V4 migration script instead:"
    echo "  just migrate-v4-rollup-dry $ROLLUP $COMPOSE_NETWORK  # for dry-run"
    echo "  just migrate-v4-rollup $ROLLUP $COMPOSE_NETWORK      # for live migration"
    exit 1
fi

if [ "$MAJOR_VERSION" -ne 3 ]; then
    echo -e "${YELLOW}Warning: Unexpected portal version $PORTAL_VERSION${NC}"
    echo "Expected version 3.x.x for V3 migration."
    echo "Proceeding, but review carefully..."
fi

echo -e "${GREEN}✓ Portal version $PORTAL_VERSION is compatible with V3 migration${NC}"
echo ""

if [ "$IS_DRY_RUN" = "true" ]; then
    echo "========================================="
    echo "DRY RUN: Phase 2 Migration Simulation"
    echo "========================================="
    echo "The following will show detailed traces of what WOULD happen."
    echo "No transactions will be broadcast to the network."
    echo ""
else
    echo "========================================="
    echo "LIVE: Executing Phase 2 Migration"
    echo "========================================="
    echo "WARNING: This will broadcast real transactions!"
    echo ""
fi

# Determine verification flag
VERIFY_FLAG=""
if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
    echo -e "${YELLOW}Warning: Skipping verification (no ETHERSCAN_API_KEY)${NC}"
else
    VERIFY_FLAG="--verify"
fi

# Execute the V3 migration
FORGE_ARGS=(
    "script/migrate/MigrateRollupV3.s.sol:MigrateRollupV3"
    "--sig" "run(string,string,bool)"
    "--rpc-url" "$NETWORK_RPC_URL"
)

# Add verification flag if set
if [ -n "$VERIFY_FLAG" ]; then
    FORGE_ARGS+=("$VERIFY_FLAG")
fi

# Add broadcast and private key for live mode, or sender + verbosity for dry-run
if [ "$IS_DRY_RUN" = "false" ]; then
    FORGE_ARGS+=("--broadcast")
    FORGE_ARGS+=("--private-key" "$MIGRATION_PROXY_ADMIN_OWNER_KEY")
else
    # In dry-run, use the ProxyAdmin owner address from rollup config as sender
    PROXY_ADMIN_OWNER=$(jq -r '.proxyAdmin.owner' "$ROLLUP_CONFIG")
    FORGE_ARGS+=("--sender" "$PROXY_ADMIN_OWNER")
    # Add maximum verbosity for dry-run to show all console.log and traces
    FORGE_ARGS+=("-vvv")
fi

# Add function arguments
FORGE_ARGS+=("$ROLLUP" "$COMPOSE_NETWORK" "$IS_DRY_RUN")

if forge script "${FORGE_ARGS[@]}"; then
    if [ "$IS_DRY_RUN" = "true" ]; then
        echo -e "\n${GREEN}Dry run completed successfully!${NC}"
        echo "No transactions were broadcast."
        echo "Review the simulation output above."
        echo ""
        echo "To execute the migration for real, run:"
        echo "  just migrate-rollup $ROLLUP $COMPOSE_NETWORK"
    else
        echo -e "\n${GREEN}Phase 2 migration complete!${NC}"
        
        # Save migration data to structured deployment file
        echo ""
        echo "Saving migration data..."
        
        # Extract proxy addresses from rollup config
        SYSTEM_CONFIG_PROXY=$(jq -r '.l1SystemConfigAddress' "$ROLLUP_CONFIG")
        OPTIMISM_PORTAL_PROXY=$(jq -r '.optimismPortal.proxy' "$ROLLUP_CONFIG")
        L1_CROSS_DOMAIN_MESSENGER_PROXY=$(jq -r '.l1CrossDomainMessenger' "$ROLLUP_CONFIG")
        L1_STANDARD_BRIDGE_PROXY=$(jq -r '.l1StandardBridge' "$ROLLUP_CONFIG")
        L1_ERC721_BRIDGE_PROXY=$(jq -r '.l1ERC721Bridge' "$ROLLUP_CONFIG")
        
        # Extract old implementation address
        OLD_OPTIMISM_PORTAL_IMPL=$(jq -r '.optimismPortal.impl' "$ROLLUP_CONFIG")
        
        # Call save-migration script
        ./scripts/save-migration.sh \
            "$ROLLUP" \
            "$COMPOSE_NETWORK" \
            "$CHAIN_ID" \
            "false" \
            "$SYSTEM_CONFIG_PROXY" \
            "$OPTIMISM_PORTAL_PROXY" \
            "$L1_CROSS_DOMAIN_MESSENGER_PROXY" \
            "$L1_STANDARD_BRIDGE_PROXY" \
            "$L1_ERC721_BRIDGE_PROXY" \
            "$OLD_OPTIMISM_PORTAL_IMPL"
    fi
else
    echo -e "\n${RED}Migration failed!${NC}"
    exit 1
fi
