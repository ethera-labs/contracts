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
    SAVE_DEPLOY_OUTPUT=true forge script script/l1/deploy/DeploySharedInfra.s.sol --rpc-url $RPC_URL --broadcast --slow

# rollup = key under rollups in config.json (e.g. chain-100003)
l1-migrate-v3 rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/MigrateRollupV3.s.sol --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-migrate-v4 rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/MigrateRollupV4.s.sol --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-upgrade-portal-interop rollup dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/UpgradeToPortalInterop.s.sol --sig "run(bool)" {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

l1-upgrade-compose-portal rollup proofMaturityDelay dryRun="false":
    ROLLUP_NAME={{rollup}} forge script script/l1/migrate/UpgradeComposePortal.s.sol --sig "run(uint256,bool)" {{proofMaturityDelay}} {{dryRun}} --rpc-url $RPC_URL --broadcast --slow

# config = path to JSON file (see docs/guides/deploy-compose-bridge.md, Phase 3)
# Requires ROLLUP_OWNER_KEY and PROXY_ADMIN_OWNER_KEY in .env (broadcasts as two addresses)
l1-upgrade-compose-bridge config dryRun="false":
    forge script script/l1/deploy/UpgradeToComposeBridge.s.sol --sig "run(string,bool)" {{config}} {{dryRun}} --private-key $ROLLUP_OWNER_KEY --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC_URL --broadcast --slow

# Requires L1_COMPOSE_BRIDGE, L2_COMPOSE_BRIDGE, COMPOSE_PORTAL, COMPOSE_ETH_LOCKBOX, PROXY_ADMIN_OWNER_KEY in .env
l1-wire-bridges:
    PROXY_ADMIN_OWNER=$(cast wallet address --private-key $PROXY_ADMIN_OWNER_KEY) forge script script/l1/deploy/WireComposeBridges.s.sol --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# L2 bridge  (reads config.json via ROLLUP_NAME)
# ============================================================

l2-deploy-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/DeployComposeBridge.s.sol --rpc-url $RPC_URL --broadcast --slow

l2-deploy-l2l2-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/DeployAndWireComposeBridge.s.sol --rpc-url $RPC_URL --broadcast --slow

l2-wire-bridge rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/bridge/WireL2ComposeBridge.s.sol --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# L2 core  (reads config.json via ROLLUP_NAME)
# ============================================================

l2-deploy-core rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/core/DeployContracts.s.sol --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# L2 DEX  (reads config.json via ROLLUP_NAME)
# ============================================================

l2-deploy-weth rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/dex/DeployWETH.s.sol --rpc-url $RPC_URL --broadcast --slow

l2-deploy-dex-tokens rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/dex/DeployDEXTokens.s.sol --rpc-url $RPC_URL --broadcast --slow

l2-deploy-swapper rollup="test":
    ROLLUP_NAME={{rollup}} forge script script/l2/dex/DeploySwapper.s.sol --rpc-url $RPC_URL --broadcast --slow

# Fund swapper with default amounts (100 WETH, 1000 USDC, 1000 SSV)
l2-fund-swapper swapper weth usdc ssv:
    forge script script/l2/dex/FundSwapper.s.sol --sig "runDefault(address,address,address,address)" {{swapper}} {{weth}} {{usdc}} {{ssv}} --rpc-url $RPC_URL --broadcast --slow

# ============================================================
# L2 full deploy sequence per rollup (wires after bridge deploy)
# ============================================================

l2-deploy-all rollup="test":
    just l2-deploy-bridge {{rollup}}
    just l2-deploy-weth {{rollup}}
    just l2-deploy-dex-tokens {{rollup}}
