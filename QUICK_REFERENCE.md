# Quick Reference

## Setup

```sh
git submodule update --init --recursive
cp .env.example .env   # fill in private keys
forge build
```

## Test

```sh
just test
```

## L1 — deploy shared infrastructure

```sh
# 1. Fill in l1.* static fields in config.json
# 2. Set PROXY_ADMIN_OWNER_KEY + GUARDIAN_KEY + RPC_URL in .env

SAVE_DEPLOY_OUTPUT=true just l1-deploy-shared
# writes proxyAdmin, disputeGameFactory, anchorStateRegistry, ethLockbox etc. back into config.json
```

## L1 — migrate existing rollup

```sh
# 1. Add rollup under rollups in config.json with l1.* addresses filled in
# 2. Set ROLLUP_NAME + keys + RPC_URL in .env

just l1-migrate-v4 chain-100003        # live
just l1-migrate-v4 chain-100003 true   # dry run
just l1-migrate-v3 chain-100003        # V3 rollup (full upgrade)
```

## L2 — full deploy sequence

```sh
# 1. Add rollup section to config.json with owner, coordinator, l2Xdm, create2Salt
# 2. Set ROLLUP_NAME + DEPLOYER_KEY + RPC_URL in .env

just l2-deploy-bridge chain-100003
just l2-deploy-weth chain-100003
just l2-deploy-dex-tokens chain-100003
just l2-deploy-swapper chain-100003    # needs WETH_ADDRESS, USDC_ADDRESS, SSV_ADDRESS in .env
# or all at once:
just l2-deploy-all chain-100003
```

## L2 — wire after L1 bridge deploy

```sh
# set L2_COMPOSE_BRIDGE and L1_COMPOSE_BRIDGE in .env
just l2-wire-bridge chain-100003
```

## Config files

| File | Purpose | Who writes it |
|------|---------|---------------|
| `config.json` | All config: shared L1 infra + per-rollup addresses | Manual (static) + `l1-deploy-shared` (deployed addresses) |
| `.env` | Private keys + active rollup name | Manual |

## Environment variables

| Var | Used by | Example |
|-----|---------|---------|
| `PROXY_ADMIN_OWNER_KEY` | `l1-deploy-shared`, migrate scripts | `0xac09...` |
| `GUARDIAN_KEY` | `l1-deploy-shared` | `0xac09...` |
| `SAVE_DEPLOY_OUTPUT` | `l1-deploy-shared` | `true` |
| `ROLLUP_NAME` | All L1 migrate + L2 scripts | `chain-100003` |
| `DEPLOYER_KEY` | All L2 scripts | `0xac09...` |
| `RPC_URL` | All live deploy recipes | `https://...` |
| `L2_COMPOSE_BRIDGE` | `l2-wire-bridge` | `0x...` |
| `L1_COMPOSE_BRIDGE` | `l2-wire-bridge`, `l2-deploy-bridge` | `0x...` |
| `WETH_ADDRESS` | `l2-deploy-swapper` | `0x...` |
| `USDC_ADDRESS` | `l2-deploy-swapper` | `0x...` |
| `SSV_ADDRESS` | `l2-deploy-swapper` | `0x...` |
