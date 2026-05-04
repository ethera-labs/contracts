#!/usr/bin/env bash
# Save deployment addresses to deployments/compose/{NETWORK}.json with enhanced metadata

set -euo pipefail

NETWORK_NAME=$1
CHAIN_ID=$2
PROXY_ADMIN=$3
SUPERCHAIN_CONFIG_PROXY=$4
DISPUTE_GAME_FACTORY_PROXY=$5
ANCHOR_STATE_REGISTRY_PROXY=$6
ETH_LOCKBOX_PROXY=$7
DISPUTE_GAME_IMPL=$8

DEPLOYMENT_FILE="deployments/compose/${NETWORK_NAME}.json"
DEPLOYMENTS_DIR="deployments/compose"

# Create deployments directory if it doesn't exist
mkdir -p "$DEPLOYMENTS_DIR"

# Parse broadcast data for enhanced metadata
BROADCAST_DIR="broadcast/DeploySharedInfra.s.sol/$CHAIN_ID"
BROADCAST_FILE=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

if [ -z "$BROADCAST_FILE" ]; then
    echo "Error: Could not find broadcast output for DeploySharedInfra"
    exit 1
fi

# Get deployment metadata from receipts (actual onchain data)
DEPLOYMENT_BLOCK=$(jq -r '.receipts[0].blockNumber' "$BROADCAST_FILE")
DEPLOYMENT_BLOCK_DEC=$((DEPLOYMENT_BLOCK))
DEPLOYER=$(jq -r '.receipts[0].from' "$BROADCAST_FILE")
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Get transaction hashes and block numbers from receipts
PROXY_ADMIN_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$PROXY_ADMIN'") | .transactionHash' "$BROADCAST_FILE" | head -1)
PROXY_ADMIN_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$PROXY_ADMIN'") | .blockNumber' "$BROADCAST_FILE" | head -1)

SUPERCHAIN_CONFIG_PROXY_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$SUPERCHAIN_CONFIG_PROXY'") | .transactionHash' "$BROADCAST_FILE" | head -1)
SUPERCHAIN_CONFIG_PROXY_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$SUPERCHAIN_CONFIG_PROXY'") | .blockNumber' "$BROADCAST_FILE" | head -1)

DISPUTE_GAME_FACTORY_PROXY_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$DISPUTE_GAME_FACTORY_PROXY'") | .transactionHash' "$BROADCAST_FILE" | head -1)
DISPUTE_GAME_FACTORY_PROXY_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$DISPUTE_GAME_FACTORY_PROXY'") | .blockNumber' "$BROADCAST_FILE" | head -1)

ANCHOR_STATE_REGISTRY_PROXY_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$ANCHOR_STATE_REGISTRY_PROXY'") | .transactionHash' "$BROADCAST_FILE" | head -1)
ANCHOR_STATE_REGISTRY_PROXY_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$ANCHOR_STATE_REGISTRY_PROXY'") | .blockNumber' "$BROADCAST_FILE" | head -1)

ETH_LOCKBOX_PROXY_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$ETH_LOCKBOX_PROXY'") | .transactionHash' "$BROADCAST_FILE" | head -1)
ETH_LOCKBOX_PROXY_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$ETH_LOCKBOX_PROXY'") | .blockNumber' "$BROADCAST_FILE" | head -1)

DISPUTE_GAME_IMPL_TX=$(jq -r '.receipts[] | select(.contractAddress == "'$DISPUTE_GAME_IMPL'") | .transactionHash' "$BROADCAST_FILE" | head -1)
DISPUTE_GAME_IMPL_BLOCK=$(jq -r '.receipts[] | select(.contractAddress == "'$DISPUTE_GAME_IMPL'") | .blockNumber' "$BROADCAST_FILE" | head -1)

# Get implementation addresses for proxied contracts
SUPERCHAIN_CONFIG_IMPL=$(jq -r '.transactions[] | select(.contractName == "SuperchainConfig" and .transactionType == "CREATE") | .contractAddress' "$BROADCAST_FILE" | head -1)
DISPUTE_GAME_FACTORY_IMPL=$(jq -r '.transactions[] | select(.contractName == "DisputeGameFactory" and .transactionType == "CREATE") | .contractAddress' "$BROADCAST_FILE" | head -1)
ANCHOR_STATE_REGISTRY_IMPL=$(jq -r '.transactions[] | select(.contractName == "ComposeAnchorStateRegistry" and .transactionType == "CREATE") | .contractAddress' "$BROADCAST_FILE" | head -1)
ETH_LOCKBOX_IMPL=$(jq -r '.transactions[] | select(.contractName == "ComposeETHLockbox" and .transactionType == "CREATE") | .contractAddress' "$BROADCAST_FILE" | head -1)

# Get constructor arguments for each implementation
PROXY_ADMIN_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "ProxyAdmin" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)
SUPERCHAIN_CONFIG_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "SuperchainConfig" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)
DISPUTE_GAME_FACTORY_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "DisputeGameFactory" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)
ANCHOR_STATE_REGISTRY_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "ComposeAnchorStateRegistry" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)
ETH_LOCKBOX_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "ComposeETHLockbox" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)
COMPOSE_DISPUTE_GAME_CONSTRUCTOR_ARGS=$(jq -c '.transactions[] | select(.contractName == "ComposeDisputeGame" and .transactionType == "CREATE") | .arguments // []' "$BROADCAST_FILE" | head -1)

# Get initialization arguments for each proxy (from upgradeAndCall calls)
# The third argument of upgradeAndCall is the initialization data (case-insensitive matching)
SUPERCHAIN_CONFIG_INIT_DATA=$(jq -r '.transactions[] | select(.function == "upgradeAndCall(address,address,bytes)" and (.arguments[0] | ascii_downcase) == ("'$SUPERCHAIN_CONFIG_PROXY'" | ascii_downcase)) | .arguments[2]' "$BROADCAST_FILE" | head -1)
DISPUTE_GAME_FACTORY_INIT_DATA=$(jq -r '.transactions[] | select(.function == "upgradeAndCall(address,address,bytes)" and (.arguments[0] | ascii_downcase) == ("'$DISPUTE_GAME_FACTORY_PROXY'" | ascii_downcase)) | .arguments[2]' "$BROADCAST_FILE" | head -1)
ANCHOR_STATE_REGISTRY_INIT_DATA=$(jq -r '.transactions[] | select(.function == "upgradeAndCall(address,address,bytes)" and (.arguments[0] | ascii_downcase) == ("'$ANCHOR_STATE_REGISTRY_PROXY'" | ascii_downcase)) | .arguments[2]' "$BROADCAST_FILE" | head -1)
ETH_LOCKBOX_INIT_DATA=$(jq -r '.transactions[] | select(.function == "upgradeAndCall(address,address,bytes)" and (.arguments[0] | ascii_downcase) == ("'$ETH_LOCKBOX_PROXY'" | ascii_downcase)) | .arguments[2]' "$BROADCAST_FILE" | head -1)

# Create deployment JSON using jq for proper escaping
# First, ensure critical variables are not empty
for var in NETWORK_NAME CHAIN_ID DEPLOYMENT_BLOCK DEPLOYER TIMESTAMP PROXY_ADMIN PROXY_ADMIN_TX; do
    if [ -z "${!var}" ]; then
        echo "Error: Variable $var is empty"
        exit 1
    fi
done

# Convert hex block numbers to decimal
PROXY_ADMIN_BLOCK_DEC=$((PROXY_ADMIN_BLOCK))
SUPERCHAIN_CONFIG_PROXY_BLOCK_DEC=$((SUPERCHAIN_CONFIG_PROXY_BLOCK))
DISPUTE_GAME_FACTORY_PROXY_BLOCK_DEC=$((DISPUTE_GAME_FACTORY_PROXY_BLOCK))
ANCHOR_STATE_REGISTRY_PROXY_BLOCK_DEC=$((ANCHOR_STATE_REGISTRY_PROXY_BLOCK))
ETH_LOCKBOX_PROXY_BLOCK_DEC=$((ETH_LOCKBOX_PROXY_BLOCK))
DISPUTE_GAME_IMPL_BLOCK_DEC=$((DISPUTE_GAME_IMPL_BLOCK))

# Create deployment JSON
jq -n \
  --arg network_name "$NETWORK_NAME" \
  --arg chain_id "$CHAIN_ID" \
  --arg deployment_block "$DEPLOYMENT_BLOCK_DEC" \
  --arg timestamp "$TIMESTAMP" \
  --arg deployer "$DEPLOYER" \
  --arg proxy_admin "$PROXY_ADMIN" \
  --arg proxy_admin_tx "$PROXY_ADMIN_TX" \
  --arg proxy_admin_block "$PROXY_ADMIN_BLOCK_DEC" \
  --argjson proxy_admin_constructor_args "$PROXY_ADMIN_CONSTRUCTOR_ARGS" \
  --arg superchain_config_proxy "$SUPERCHAIN_CONFIG_PROXY" \
  --arg superchain_config_impl "$SUPERCHAIN_CONFIG_IMPL" \
  --arg superchain_config_tx "$SUPERCHAIN_CONFIG_PROXY_TX" \
  --arg superchain_config_block "$SUPERCHAIN_CONFIG_PROXY_BLOCK_DEC" \
  --argjson superchain_config_constructor_args "$SUPERCHAIN_CONFIG_CONSTRUCTOR_ARGS" \
  --arg superchain_config_init_data "$SUPERCHAIN_CONFIG_INIT_DATA" \
  --arg dispute_game_factory_proxy "$DISPUTE_GAME_FACTORY_PROXY" \
  --arg dispute_game_factory_impl "$DISPUTE_GAME_FACTORY_IMPL" \
  --arg dispute_game_factory_tx "$DISPUTE_GAME_FACTORY_PROXY_TX" \
  --arg dispute_game_factory_block "$DISPUTE_GAME_FACTORY_PROXY_BLOCK_DEC" \
  --argjson dispute_game_factory_constructor_args "$DISPUTE_GAME_FACTORY_CONSTRUCTOR_ARGS" \
  --arg dispute_game_factory_init_data "$DISPUTE_GAME_FACTORY_INIT_DATA" \
  --arg anchor_state_registry_proxy "$ANCHOR_STATE_REGISTRY_PROXY" \
  --arg anchor_state_registry_impl "$ANCHOR_STATE_REGISTRY_IMPL" \
  --arg anchor_state_registry_tx "$ANCHOR_STATE_REGISTRY_PROXY_TX" \
  --arg anchor_state_registry_block "$ANCHOR_STATE_REGISTRY_PROXY_BLOCK_DEC" \
  --argjson anchor_state_registry_constructor_args "$ANCHOR_STATE_REGISTRY_CONSTRUCTOR_ARGS" \
  --arg anchor_state_registry_init_data "$ANCHOR_STATE_REGISTRY_INIT_DATA" \
  --arg eth_lockbox_proxy "$ETH_LOCKBOX_PROXY" \
  --arg eth_lockbox_impl "$ETH_LOCKBOX_IMPL" \
  --arg eth_lockbox_tx "$ETH_LOCKBOX_PROXY_TX" \
  --arg eth_lockbox_block "$ETH_LOCKBOX_PROXY_BLOCK_DEC" \
  --argjson eth_lockbox_constructor_args "$ETH_LOCKBOX_CONSTRUCTOR_ARGS" \
  --arg eth_lockbox_init_data "$ETH_LOCKBOX_INIT_DATA" \
  --arg compose_dispute_game "$DISPUTE_GAME_IMPL" \
  --arg compose_dispute_game_tx "$DISPUTE_GAME_IMPL_TX" \
  --arg compose_dispute_game_block "$DISPUTE_GAME_IMPL_BLOCK_DEC" \
  --argjson compose_dispute_game_constructor_args "$COMPOSE_DISPUTE_GAME_CONSTRUCTOR_ARGS" \
  '{
    ($network_name): {
      chainId: ($chain_id | tonumber),
      deployment_block: ($deployment_block | tonumber),
      timestamp: $timestamp,
      deployer: $deployer,
      contracts: {
        ProxyAdmin: {
          proxyAddress: "",
          implAddress: $proxy_admin,
          constructorArgs: $proxy_admin_constructor_args,
          txHash: $proxy_admin_tx,
          deploymentBlock: ($proxy_admin_block | tonumber)
        },
        SuperchainConfig: {
          proxyAddress: $superchain_config_proxy,
          implAddress: $superchain_config_impl,
          constructorArgs: $superchain_config_constructor_args,
          initializeData: $superchain_config_init_data,
          txHash: $superchain_config_tx,
          deploymentBlock: ($superchain_config_block | tonumber)
        },
        DisputeGameFactory: {
          proxyAddress: $dispute_game_factory_proxy,
          implAddress: $dispute_game_factory_impl,
          constructorArgs: $dispute_game_factory_constructor_args,
          initializeData: $dispute_game_factory_init_data,
          txHash: $dispute_game_factory_tx,
          deploymentBlock: ($dispute_game_factory_block | tonumber)
        },
        AnchorStateRegistry: {
          proxyAddress: $anchor_state_registry_proxy,
          implAddress: $anchor_state_registry_impl,
          constructorArgs: $anchor_state_registry_constructor_args,
          initializeData: $anchor_state_registry_init_data,
          txHash: $anchor_state_registry_tx,
          deploymentBlock: ($anchor_state_registry_block | tonumber)
        },
        ETHLockbox: {
          proxyAddress: $eth_lockbox_proxy,
          implAddress: $eth_lockbox_impl,
          constructorArgs: $eth_lockbox_constructor_args,
          initializeData: $eth_lockbox_init_data,
          txHash: $eth_lockbox_tx,
          deploymentBlock: ($eth_lockbox_block | tonumber)
        },
        ComposeDisputeGame: {
          proxyAddress: "",
          implAddress: $compose_dispute_game,
          constructorArgs: $compose_dispute_game_constructor_args,
          txHash: $compose_dispute_game_tx,
          deploymentBlock: ($compose_dispute_game_block | tonumber)
        }
      }
    }
  }' > "$DEPLOYMENT_FILE"

echo ""
echo "✓ Deployment addresses saved to $DEPLOYMENT_FILE"
echo ""
echo "=== Enhanced Deployment Summary for $NETWORK_NAME ==="
echo "Chain ID:                    $CHAIN_ID"
echo "Deployment Block:            $DEPLOYMENT_BLOCK"
echo "Deployer:                    $DEPLOYER"
echo "Timestamp:                   $TIMESTAMP"
echo ""
echo "Governance:"
echo "  ProxyAdmin:                $PROXY_ADMIN"
echo "  SuperchainConfig (Proxy):  $SUPERCHAIN_CONFIG_PROXY"
echo ""
echo "Settlement:"
echo "  DisputeGameFactory (Proxy): $DISPUTE_GAME_FACTORY_PROXY"
echo "  AnchorStateRegistry (Proxy): $ANCHOR_STATE_REGISTRY_PROXY"
echo "  ComposeDisputeGame (Impl):   $DISPUTE_GAME_IMPL"
echo ""
echo "Liquidity:"
echo "  ETHLockbox (Proxy):        $ETH_LOCKBOX_PROXY"
echo ""
echo "Deployment file:             $DEPLOYMENT_FILE"
echo "========================================"
