#!/usr/bin/env bash
# Parse network configuration from networks.toml

set -euo pipefail

NETWORK_NAME=$1

if [ ! -f networks.toml ]; then
    echo "Error: networks.toml not found"
    exit 1
fi

# Check if network exists in config
if ! grep -q "^\[networks\.$NETWORK_NAME\]" networks.toml; then
    echo "Error: Network '$NETWORK_NAME' not found in networks.toml"
    echo "Available networks:"
    grep "^\[networks\." networks.toml | sed 's/\[networks\.//g' | sed 's/\]//g' | sed 's/^/  - /g'
    exit 1
fi

# Parse network config using awk
parse_value() {
    local key=$1
    awk -F= -v network="$NETWORK_NAME" -v key="$key" '
        /^\[networks\./ { current_network = $0; gsub(/^\[networks\./, "", current_network); gsub(/\].*$/, "", current_network) }
        current_network == network && $1 ~ "^"key {
            value = $2
            gsub(/^[[:space:]]*"?/, "", value)
            gsub(/"?[[:space:]]*$/, "", value)
            gsub(/#.*$/, "", value)
            gsub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' networks.toml
}

# Export NETWORK_NAME for ComposeConfig.sol to read
export NETWORK_NAME

# Export network configuration (for scripts that need them)
export NETWORK_RPC_URL=$(parse_value "rpc_url")
export NETWORK_CHAIN_ID=$(parse_value "chain_id")
export NETWORK_EXPLORER_URL=$(parse_value "explorer_url")
export NETWORK_EXPLORER_API_URL=$(parse_value "explorer_api_url")

# Load .env for private key and API key
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Validation - only check required env vars (private key)
# All other config is validated by ComposeConfig.sol when deployment runs
if [ -z "$DEPLOYER_PRIVATE_KEY" ] && [ -z "$PRIVATE_KEY" ]; then
    echo "Error: DEPLOYER_PRIVATE_KEY or PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Warning: ETHERSCAN_API_KEY not set in .env. Verification will be skipped."
fi

echo "✓ Network configuration loaded for: $NETWORK_NAME"
echo "  All deployment parameters will be read from networks.toml by ComposeConfig.sol"
