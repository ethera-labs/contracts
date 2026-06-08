# Contract Parameters Guide

Detailed explanation of all contract initialization parameters and their purposes.

## Overview

The Compose Contracts deployment involves three main contracts, each with specific initialization parameters. This guide explains what each parameter means, how to obtain it, and best practices for configuration.

## ComposeL2OutputOracle Parameters

The ComposeL2OutputOracle is an upgradeable proxy contract that manages L2 output proposals with SP1 proof verification.

### Parameters Summary

| Parameter | Type | Description | Required |
|-----------|------|-------------|----------|
| `verifier_address` | address | SP1Verifier contract address | Yes |
| `owner_address` | address | Admin owner address | Yes |
| `proposer_address` | address | Approved proposer address | Yes |
| `aggregation_vkey` | bytes32 | SP1 verification key | Yes |
| `starting_superblock_number` | uint256 | Starting block number | Yes |

### 1. verifier_address

**Type:** `address`

**Purpose:**
The address of the deployed SP1Verifier contract that verifies zero-knowledge proofs for L2 state transitions.

**What it does:**
- Validates SP1 proofs submitted with L2 outputs
- Ensures cryptographic correctness of state transitions
- Called by `proposeL2Output()` function

**How to obtain:**
```bash
# Option 1: Use existing SP1Verifier deployment
# Check SP1 documentation for canonical deployments

# Option 2: Deploy your own SP1Verifier
# Follow SP1 deployment guide

# Option 3: For testing, use a mock verifier
```

**Example:**
```toml
verifier_address = "0x17Ef331C3c90E9e5718e81085c721a404eF18436"
```

**Validation:**
```bash
# Verify it's a contract (not EOA)
cast code $VERIFIER_ADDRESS --rpc-url $RPC_URL

# Check it implements ISP1Verifier interface
cast call $VERIFIER_ADDRESS "verifyProof(bytes32,bytes,bytes)" --rpc-url $RPC_URL
```

**Security considerations:**
- Must be a trusted SP1Verifier implementation
- Should be audited and verified
- Can be updated by owner after deployment

### 2. owner_address

**Type:** `address`

**Purpose:**
The administrative owner address with permissions to update critical contract parameters.

**What it can do:**
- Update aggregation verification key (`setAggregationVkey`)
- Update verifier contract address (`setVerifier`)
- Update approved proposer address (`setApprovedProposer`)
- Perform critical admin functions

**Best practices:**
- **Testnet:** Can be a regular EOA for testing
- **Mainnet:** Should be a multisig (Gnosis Safe)
- Never use the deployer wallet
- Use hardware wallet or secure key management

**Example:**
```toml
# Testnet - EOA
owner_address = "0xA139A1776E60F9645533a9AD419461818D6839a1"

# Mainnet - Multisig
owner_address = "0x1234567890123456789012345678901234567890"  # Gnosis Safe
```

**Setting up a multisig:**
```bash
# Create Gnosis Safe at https://app.safe.global/
# Or use existing multisig deployment
# Recommended: 3-of-5 or 2-of-3 threshold
```

**Validation:**
```bash
# Check address has funds for transactions
cast balance $OWNER_ADDRESS --rpc-url $RPC_URL

# If multisig, verify it's deployed
cast code $OWNER_ADDRESS --rpc-url $RPC_URL
```

### 3. proposer_address

**Type:** `address`

**Purpose:**
The only address authorized to propose L2 outputs to the oracle.

**What it does:**
- Submits L2 state roots and proofs
- Called by the sequencer/proposer service
- Checked via `tx.origin` in `proposeL2Output()`

**How it works:**
```solidity
function proposeL2Output(
    bytes32 _outputRoot,
    bytes32 _l1Hash,
    bytes memory _extraData
) external {
    if (tx.origin != approvedProposer) {
        revert UnauthorizedProposer();
    }
    // ... rest of logic
}
```

**Best practices:**
- Use a dedicated service wallet
- Keep private keys secure (HSM, KMS, etc.)
- Monitor proposer activity
- Have backup proposer ready
- Can be updated by owner

**Example:**
```toml
proposer_address = "0xb054981b2Ef67603E50B1bD840D0834ef5bcceE4"
```

**Security considerations:**
- Compromise of proposer key allows malicious proposals
- Should be a hot wallet for the proposer service
- Use key rotation strategy
- Monitor all proposals

**Testing:**
```bash
# Verify proposer has funds for gas
cast balance $PROPOSER_ADDRESS --rpc-url $RPC_URL

# Test proposer can submit (after deployment)
# Run proposer service with this key
```

### 4. aggregation_vkey

**Type:** `bytes32` (32-byte hex string)

**Purpose:**
The verification key for the SP1 aggregation program that validates L2 state transitions.

**What it does:**
- Used by SP1Verifier to validate proofs
- Specific to your SP1 circuit implementation
- Must match the proving key used to generate proofs

**Format:**
```
0x[64 hex characters]
```

**How to obtain:**
```bash
# Generated during SP1 program build
# Located in your SP1 project output
# Example: sp1-aggregation/vkey.json

# Extract vkey from SP1 build artifacts
jq -r '.vkey' path/to/vkey.json
```

**Example:**
```toml
aggregation_vkey = "0x0059ae2f8c8ad61a6af02594067148b58dbecff2e3352170923efda8ea603f1e"
```

**Validation:**
```bash
# Ensure it's exactly 32 bytes (64 hex chars + 0x prefix)
echo $VKEY | grep -E '^0x[0-9a-fA-F]{64}$'

# Verify it matches your SP1 program
# Compare with output from SP1 build
```

**Important notes:**
- Different SP1 programs have different vkeys
- Testnet and mainnet can use different vkeys
- Can be updated by owner after deployment
- Mismatch causes all proof verifications to fail

### 5. starting_superblock_number

**Type:** `uint256`

**Purpose:**
The starting superblock number for the oracle. Defines the initial state of the L2.

**What it does:**
- Sets the initial `superBlockNumber` state variable
- Usually `0` for new deployments
- Can be non-zero when migrating from another oracle

**Common values:**
```toml
# New deployment - start from genesis
starting_superblock_number = 0

# Migration - continue from existing state
starting_superblock_number = 12345
```

**When to use non-zero:**
- Migrating from another L2OutputOracle
- Continuing from a previous deployment
- Upgrading oracle implementation

**Validation:**
```bash
# For new deployment, should be 0
# For migration, verify it matches source oracle:
cast call $OLD_ORACLE "latestSuperblockNumber()" --rpc-url $RPC_URL
```

## DisputeGameFactory Parameters

The DisputeGameFactory is a factory contract for creating dispute game instances.

### Parameters Summary

| Parameter | Type | Description | Required |
|-----------|------|-------------|----------|
| `admin_address` | address | Factory admin address | Yes |

### admin_address

**Type:** `address`

**Purpose:**
The administrative address that controls the DisputeGameFactory.

**What it can do:**
- Register new game types (`setGameImplementation`)
- Update game implementations
- Set initial bonds
- Manage factory configuration

**Best practices:**
- **Testnet:** Can be same as oracle owner
- **Mainnet:** Should be a multisig
- Use hardware wallet or secure key management
- Can be different from oracle owner

**Example:**
```toml
# Same as oracle owner
admin_address = "0xA139A1776E60F9645533a9AD419461818D6839a1"

# Or separate multisig
admin_address = "0x9876543210987654321098765432109876543210"
```

**Validation:**
```bash
# Check address has funds
cast balance $ADMIN_ADDRESS --rpc-url $RPC_URL

# If multisig, verify deployment
cast code $ADMIN_ADDRESS --rpc-url $RPC_URL
```

## Parameter Configuration Examples

### Development/Testing Environment

```toml
[networks.sepolia-dev]
name = "Sepolia Development"
rpc_url = "https://eth-sepolia.g.alchemy.com/v2/DEV_KEY"
chain_id = 11155111
explorer_url = "https://sepolia.etherscan.io"
explorer_api_url = "https://api-sepolia.etherscan.io/api"

# Testing parameters - can use EOAs
verifier_address = "0x17Ef331C3c90E9e5718e81085c721a404eF18436"
owner_address = "0xDevelopmentOwnerEOA..."
proposer_address = "0xDevelopmentProposerEOA..."
aggregation_vkey = "0x00TEST1234567890..." 
starting_superblock_number = 0
admin_address = "0xDevelopmentOwnerEOA..."
```

### Staging Environment

```toml
[networks.sepolia-staging]
name = "Sepolia Staging"
rpc_url = "https://eth-sepolia.g.alchemy.com/v2/STAGING_KEY"
chain_id = 11155111
explorer_url = "https://sepolia.etherscan.io"
explorer_api_url = "https://api-sepolia.etherscan.io/api"

# Production-like parameters
verifier_address = "0x17Ef331C3c90E9e5718e81085c721a404eF18436"
owner_address = "0xStagingMultisig..."  # 2-of-3 multisig
proposer_address = "0xStagingProposerService..."
aggregation_vkey = "0x0059ae2f8c8ad61a6af02594067148b58dbecff2e3352170923efda8ea603f1e"
starting_superblock_number = 0
admin_address = "0xStagingMultisig..."
```

### Production Environment

```toml
[networks.mainnet]
name = "Ethereum Mainnet"
rpc_url = "https://eth-mainnet.g.alchemy.com/v2/PROD_KEY"
chain_id = 1
explorer_url = "https://etherscan.io"
explorer_api_url = "https://api.etherscan.io/api"

# Production parameters - maximum security
verifier_address = "0xProductionSP1Verifier..."
owner_address = "0xProductionMultisig..."  # 3-of-5 multisig
proposer_address = "0xProductionProposerService..."
aggregation_vkey = "0xProductionVkey..."
starting_superblock_number = 0
admin_address = "0xProductionMultisig..."  # Can be same or different
```

## Parameter Relationships

### Owner vs Admin

```
ComposeL2OutputOracle.owner_address
  ├── Controls oracle parameters
  ├── Updates verifier, proposer, vkey
  └── Can be same as admin_address

DisputeGameFactory.admin_address
  ├── Controls factory configuration
  ├── Manages game implementations
  └── Can be same as owner_address
```

**Recommendation:**
- For simplicity: Use same address
- For security: Use separate addresses with different multisig members

### Proposer vs Owner

```
proposer_address (Hot Wallet)
  ├── High-frequency operations
  ├── Submits L2 outputs continuously
  └── Needs to be readily available

owner_address (Cold/Multisig)
  ├── Infrequent operations
  ├── Admin functions only
  └── Maximum security
```

**Important:** Never use same address for both!

## Common Mistakes

### ❌ Using Deployer Wallet as Owner

```toml
# BAD - Don't do this!
owner_address = "0xDeployerWallet..."
```

**Why it's bad:**
- Deployer key often exposed during deployment
- Single point of failure
- No recovery mechanism

**Better:**
```toml
# GOOD - Use dedicated owner
owner_address = "0xDedicatedMultisig..."
```

### ❌ Same Address for Owner and Proposer

```toml
# BAD - Security risk!
owner_address = "0xSameAddress..."
proposer_address = "0xSameAddress..."
```

**Why it's bad:**
- Proposer needs to be hot wallet
- Owner should be cold/multisig
- Compromise of proposer = compromise of admin

### ❌ Wrong Verification Key

```toml
# BAD - Copy-paste error
aggregation_vkey = "0x0000000000000000..."  # Default/placeholder
```

**Result:**
- All proof verifications fail
- L2 output proposals rejected
- System unusable

**Check:**
```bash
# Verify vkey matches your SP1 build
diff <(echo $CONFIGURED_VKEY) <(jq -r '.vkey' sp1-build/vkey.json)
```

### ❌ Invalid Verifier Address

```toml
# BAD - EOA instead of contract
verifier_address = "0xEOAAddress..."
```

**Result:**
- Calls to verifier fail
- Proposals cannot be submitted
- Deployment non-functional

**Check:**
```bash
# Must return bytecode, not 0x
cast code $VERIFIER_ADDRESS --rpc-url $RPC_URL
```

## Security Checklist

### Before Deployment

- [ ] All addresses are checksummed (mixed case)
- [ ] Verifier address is a valid contract
- [ ] Owner address is a multisig (mainnet)
- [ ] Proposer address is different from owner
- [ ] Aggregation vkey matches SP1 build output
- [ ] Admin address is a multisig (mainnet)
- [ ] All addresses have been tested on testnet
- [ ] Private keys are securely stored

### After Deployment

- [ ] Verify owner address has correct permissions
- [ ] Test proposer can submit outputs
- [ ] Verify aggregation vkey is correct
- [ ] Test owner admin functions work
- [ ] Verify admin can manage factory
- [ ] Document all parameters
- [ ] Backup configuration securely

## Parameter Update Operations

### Updating After Deployment

Some parameters can be updated by the owner:

```bash
# Update aggregation vkey
cast send $ORACLE_PROXY "setAggregationVkey(bytes32)" $NEW_VKEY \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY

# Update verifier address
cast send $ORACLE_PROXY "setVerifier(address)" $NEW_VERIFIER \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY

# Update proposer address
cast send $ORACLE_PROXY "setApprovedProposer(address)" $NEW_PROPOSER \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

**Note:** These are admin functions marked as "TODO remove in prod" in the contract. For production, consider removing these update functions or adding timelock/governance.

## Testing Parameters

### Testnet Testing

```bash
# 1. Deploy with test parameters
just deploy-network sepolia

# 2. Verify deployment
ORACLE=$(just get-deployment sepolia | jq -r '.ComposeL2OutputOracle.proxy')

# 3. Check parameters
cast call $ORACLE "verifier()" --rpc-url $RPC_URL
cast call $ORACLE "owner()" --rpc-url $RPC_URL
cast call $ORACLE "approvedProposer()" --rpc-url $RPC_URL
cast call $ORACLE "aggregationVkey()" --rpc-url $RPC_URL

# 4. Test proposer submission (requires proposer key)
# Run your proposer service
```

## References

- [NETWORK_CONFIG.md](NETWORK_CONFIG.md) - Network configuration guide
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Full deployment walkthrough
- [SP1 Documentation](https://docs.succinct.xyz/) - SP1 proof system
- [Gnosis Safe](https://safe.global/) - Multisig wallet
