#!/usr/bin/env bash
# Main deployment orchestrator for Compose Contracts

set -euo pipefail

NETWORK_NAME=$1

echo "========================================="
echo "Deploying Compose Contracts to $NETWORK_NAME"
echo "========================================="
echo ""

# Parse network configuration (sets NETWORK_NAME env var and validates .env)
source scripts/parse-network.sh "$NETWORK_NAME"

echo "Network:     $NETWORK_NAME"
echo "Chain ID:    $NETWORK_CHAIN_ID"
echo "RPC URL:     $NETWORK_RPC_URL"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq."
    exit 1
fi

# =============================================================================
# Deploy Phase 1: Shared Infrastructure
# =============================================================================
echo "========================================="
echo "Deploying Phase 1: Shared Infrastructure"
echo "========================================="
echo ""

# Set private key env var (ComposeConfig reads PRIVATE_KEY)
export PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-$PRIVATE_KEY}"

# Deploy with verification
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    forge script script/deploy/DeploySharedInfra.s.sol:DeploySharedInfra \
        --rpc-url "$NETWORK_RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --sig "run()" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_API_KEY"
else
    echo "Warning: Skipping verification (no ETHERSCAN_API_KEY)"
    forge script script/deploy/DeploySharedInfra.s.sol:DeploySharedInfra \
        --rpc-url "$NETWORK_RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --sig "run()" \
        --broadcast
fi

# Parse deployment addresses from broadcast output
BROADCAST_DIR="broadcast/DeploySharedInfra.s.sol/$NETWORK_CHAIN_ID"
BROADCAST_FILE=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

if [ -z "$BROADCAST_FILE" ]; then
    echo "Error: Could not find broadcast output for DeploySharedInfra"
    exit 1
fi

# Extract deployed contract addresses
PROXY_ADMIN=$(jq -r '.transactions[] | select(.contractName == "ProxyAdmin") | .contractAddress' "$BROADCAST_FILE" | head -1)

# Get all Proxy deployments in order (they are deployed as: SuperchainConfig, DisputeGameFactory, AnchorStateRegistry, ETHLockbox)
PROXY_ADDRESSES=($(jq -r '.transactions[] | select(.contractName == "Proxy" and .transactionType == "CREATE") | .contractAddress' "$BROADCAST_FILE"))
SUPERCHAIN_CONFIG_PROXY="${PROXY_ADDRESSES[0]}"
DISPUTE_GAME_FACTORY_PROXY="${PROXY_ADDRESSES[1]}"
ANCHOR_STATE_REGISTRY_PROXY="${PROXY_ADDRESSES[2]}"
ETH_LOCKBOX_PROXY="${PROXY_ADDRESSES[3]}"

# Get ComposeDisputeGame implementation
DISPUTE_GAME_IMPL=$(jq -r '.transactions[] | select(.contractName == "ComposeDisputeGame") | .contractAddress' "$BROADCAST_FILE" | head -1)

echo ""
echo "✓ Phase 1 deployment complete:"
echo "  ProxyAdmin:              $PROXY_ADMIN"
echo "  SuperchainConfig:        $SUPERCHAIN_CONFIG_PROXY"
echo "  DisputeGameFactory:      $DISPUTE_GAME_FACTORY_PROXY"
echo "  AnchorStateRegistry:     $ANCHOR_STATE_REGISTRY_PROXY"
echo "  ETHLockbox:              $ETH_LOCKBOX_PROXY"
echo "  ComposeDisputeGame:      $DISPUTE_GAME_IMPL"
echo ""

# =============================================================================
# Save deployment addresses
# =============================================================================
./scripts/save-deployment.sh \
    "$NETWORK_NAME" \
    "$NETWORK_CHAIN_ID" \
    "$PROXY_ADMIN" \
    "$SUPERCHAIN_CONFIG_PROXY" \
    "$DISPUTE_GAME_FACTORY_PROXY" \
    "$ANCHOR_STATE_REGISTRY_PROXY" \
    "$ETH_LOCKBOX_PROXY" \
    "$DISPUTE_GAME_IMPL"

echo ""
echo "========================================="
echo "✓ Deployment to $NETWORK_NAME complete!"
echo "📁 Deployment saved to: deployments/compose/$NETWORK_NAME.json"
echo "========================================="
