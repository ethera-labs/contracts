#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ROLLUP=$1
DRY_RUN=${2:-dry-run}

# Check if rollup parameter is provided
if [ -z "$ROLLUP" ]; then
    echo -e "${RED}Error: Rollup parameter required${NC}"
    echo "Usage: $0 <rollup> [dry-run|live]"
    echo "Example: $0 unichain-stage dry-run"
    echo "Example: $0 unichain-stage live"
    exit 1
fi

# Check if rollup config exists
ROLLUP_CONFIG="script/config/rollups/${ROLLUP}.json"
if [ ! -f "$ROLLUP_CONFIG" ]; then
    echo -e "${RED}Error: Rollup configuration not found: $ROLLUP_CONFIG${NC}"
    exit 1
fi

# Determine if this is a dry run
IS_DRY_RUN=true
if [ "$DRY_RUN" = "live" ]; then
    IS_DRY_RUN=false
fi

# Check for MIGRATION_PROXY_ADMIN_OWNER_KEY (required for live mode)
if [ "$IS_DRY_RUN" = "false" ]; then
    if [ -z "${MIGRATION_PROXY_ADMIN_OWNER_KEY:-}" ]; then
        echo -e "${RED}Error: MIGRATION_PROXY_ADMIN_OWNER_KEY not set in .env${NC}"
        echo "This private key is required to upgrade the portal."
        echo "Add it to your .env file with the Rollup ProxyAdmin owner private key."
        exit 1
    fi
fi

echo "========================================="
echo "Portal Interop Upgrade"
echo "========================================="
echo "Rollup: $ROLLUP"
echo "Mode: $([ "$IS_DRY_RUN" = "true" ] && echo "DRY RUN" || echo "LIVE")"
echo ""

# Get portal address and check version
PORTAL_PROXY=$(jq -r '.optimismPortal.proxy' "$ROLLUP_CONFIG")
NETWORK_RPC_URL=${NETWORK_RPC_URL:-"https://ethereum-sepolia-rpc.publicnode.com"}

echo "Detecting portal type..."
PORTAL_VERSION=$(cast call "$PORTAL_PROXY" "version()(string)" --rpc-url "$NETWORK_RPC_URL" 2>&1 || echo "")

if [ -z "$PORTAL_VERSION" ]; then
    echo -e "${RED}Error: Could not read portal version${NC}"
    exit 1
fi

echo "  Portal version: $PORTAL_VERSION"

# Check if already OptimismPortalInterop
HAS_SUPER_ROOTS=$(cast call "$PORTAL_PROXY" "superRootsActive()(bool)" --rpc-url "$NETWORK_RPC_URL" 2>&1 || echo "FAIL")

if [ "$HAS_SUPER_ROOTS" != "FAIL" ]; then
    echo -e "${GREEN}Portal already has superRootsActive() function${NC}"
    echo "This portal is likely already OptimismPortalInterop."
    echo "You can proceed directly to V4 migration:"
    echo "  just migrate-v4-rollup-dry $ROLLUP <compose-network>"
    exit 0
fi

echo -e "${YELLOW}Portal is standard OptimismPortal2 - upgrade needed${NC}"
echo ""

# Run the upgrade
if [ "$IS_DRY_RUN" = "true" ]; then
    echo "Running upgrade simulation..."
    forge script script/migrate/UpgradeToPortalInterop.s.sol:UpgradeToPortalInterop \
        --rpc-url "$NETWORK_RPC_URL" \
        --sender $(jq -r '.proxyAdmin.owner' "$ROLLUP_CONFIG") \
        --unlocked \
        -vvv \
        --sig "run(string,bool)" \
        "$ROLLUP" \
        true
else
    echo "Executing live upgrade..."
    forge script script/migrate/UpgradeToPortalInterop.s.sol:UpgradeToPortalInterop \
        --rpc-url "$NETWORK_RPC_URL" \
        --private-key "$MIGRATION_PROXY_ADMIN_OWNER_KEY" \
        --broadcast \
        --verify \
        -vvv \
        --sig "run(string,bool)" \
        "$ROLLUP" \
        false
fi

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ Upgrade successful!${NC}"
    if [ "$IS_DRY_RUN" = "false" ]; then
        echo ""
        echo "Next steps:"
        echo "1. Verify the upgrade on block explorer"
        echo "2. Run V4 migration to connect to Compose:"
        echo "   just migrate-v4-rollup-dry $ROLLUP <compose-network>"
    fi
else
    echo -e "${RED}✗ Upgrade failed!${NC}"
    exit $EXIT_CODE
fi
