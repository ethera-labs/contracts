<p align="center"><img src="https://framerusercontent.com/images/9FedKxMYLZKR9fxBCYj90z78.png?scale-down-to=512&width=893&height=363" alt="SSV Network"></p>


<a href="https://discord.com/invite/ssvnetworkofficial"><img src="https://img.shields.io/badge/discord-%23ssvlabs-8A2BE2.svg" alt="Discord" /></a>

# Compose Network Contracts

⚠️ **WARNING: HEAVY DEVELOPMENT** ⚠️

This project is currently in **heavy development phase** and has **NOT been audited**. The contracts are **NOT production-ready** and should not be used in mainnet environments or with real assets. Use at your own risk.

---

This repository contains the smart contracts for the Compose Network, organized into two main components:

## Repository Structure

```
compose-contracts/
├── L1-settlement/          # L1 settlement layer contracts
│   ├── src/               # ComposeDisputeGame, ComposeAnchorStateRegistry, ComposeETHLockbox
│   ├── script/            # Deployment scripts
│   ├── test/              # Contract tests
│   ├── justfile           # Deployment commands
│   └── README.md          # L1 documentation
│
└── L2/                    # L2 execution layer contracts
    ├── src/               # Mailbox, Bridge, PingPong, BridgeableToken
    ├── script/            # Deployment scripts
    ├── test/              # Contract tests
    ├── justfile           # Deployment commands
    └── README.md          # L2 documentation
```

## Components

### L1-settlement

The L1 settlement layer contracts handle:
- **ComposeDisputeGame** - Handles dispute resolution for L2 outputs  
- **ComposeAnchorStateRegistry** - Tracks finalized superblock anchor states 
- **ComposeETHLockbox** - Manages ETH liquidity locking and unlocking for authorized OptimismPortals, enabling unified ETH liquidity management across chains in the superchain cluster. Modified to use SuperchainConfig directly instead of SystemConfig for simpler cluster-wide governance.  

**📚 Full documentation:** [L1-settlement/README.md](L1-settlement/README.md)

**Quick start:**
```bash
cd L1-settlement
just setup
just build
just deploy-network sepolia
```

### L2

The L2 execution layer contracts handle:
- **Mailbox** - Cross-rollup message handling and coordination
- **PingPong** - Cross-rollup messaging demonstration
- **Bridge** - Asset bridging between rollups
- **BridgeableToken** - Token with cross-rollup support

**Full documentation:** [L2/README.md](L2/README.md)

**Quick start:**
```bash
cd L2
just init-config
just build
just deploy-network rollup-a
```

## Getting Started

### Important for new deployments

To perform a new deployment, open a new PR with the updated `deployments.json` file. Please specify unique network names.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [just](https://github.com/casey/just#installation)
- [jq](https://stedolan.github.io/jq/)

### Installation

```bash
# Clone repository
git clone https://github.com/compose-network/compose-contracts.git
cd compose-contracts

# Initialize submodules
git submodule update --init --recursive

# For L1 deployment
cd L1-settlement
just setup
just build

# For L2 deployment
cd ../L2
just init-config  # Create config files
just build
just deploy-network rollup-a
```

## 📖 Documentation

### Repository Structure & Setup
- **[Quick Reference](QUICK_REFERENCE.md)** - Essential commands

### L1 Settlement Layer
- **[L1 README](L1-settlement/README.md)** - Main L1 documentation
- **[Quick Start](L1-settlement/GETTING_STARTED.md)** - Get started guide
- **[Deployment Guide](L1-settlement/docs/DEPLOYMENT_GUIDE.md)** - Deploy contracts
- **[Network Configuration](L1-settlement/docs/NETWORK_CONFIG.md)** - Configure networks
- **[Contract Parameters](L1-settlement/docs/CONTRACT_PARAMS.md)** - Parameter reference

### L2 Execution Layer
- **[L2 README](L2/README.md)** - Main L2 documentation
- **[Quick Start](L2/GETTING_STARTED.md)** - Get started guide
- **[Deployment Scripts](L2/script/)** - Deployment implementations

## Architecture

```
┌─────────────────────────────────────────┐
│          L1 Networks                    │
│  (Ethereum, Hoodi, etc.)                │
│                                         │
│  ┌────────────────────────────────────┐ │
│  │  ComposeL2OutputOracle (Proxy)     │ │
│  │  - Verifies L2 state roots         │ │
│  │  - Uses SP1 proofs                 │ │
│  └────────────────────────────────────┘ │
│                                         │
│  ┌────────────────────────────────────┐ │
│  │  ComposeDisputeGame                │ │
│  │  - Dispute resolution              │ │
│  └────────────────────────────────────┘ │
│                                         │
│  ┌────────────────────────────────────┐ │
│  │  DisputeGameFactory                │ │
│  │  - Creates dispute games           │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
                    ↕
┌─────────────────────────────────────────┐
│          L2 Network                     │
│  (Compose core contracts)               │
└─────────────────────────────────────────┘
```

## Links

- [Compose Network Documentation](https://docs.compose.network) (if available)
- [Optimism Bedrock](https://github.com/ethereum-optimism/optimism)
- [SP1 Documentation](https://docs.succinct.xyz/)

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [just](https://github.com/casey/just#installation)
- [jq](https://stedolan.github.io/jq/)

This project is licensed under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

See the [LICENSE](LICENSE) file for the complete license text.

### Third-Party Licenses

This project incorporates several open-source libraries with permissive licenses (MIT/Apache-2.0) that are compatible with GPL-3.0-or-later. For detailed information about third-party dependencies and their licenses, see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

### Important for new deployments

We welcome contributions from the community! Whether you're fixing bugs, improving documentation, or proposing new features, your input is valued.

### How to Contribute

1. **Report Issues**: Found a bug or have a feature request? Please [open an issue](https://github.com/compose-network/compose-contracts/issues) with a clear description.

2. **Submit Pull Requests**: 
   - Fork the repository
   - Create a feature branch (`git checkout -b feature/your-feature-name`)
   - Make your changes with clear, descriptive commits
   - Ensure all tests pass and add new tests for new features
   - Submit a pull request with a comprehensive description of changes

3. **Code Standards**:
   - Follow existing code style and conventions
   - Include inline documentation for complex logic
   - Update relevant documentation (README, docs/) when necessary
   - Ensure all contracts include proper SPDX license identifiers

4. **Licensing**: By contributing to this project, you agree that your contributions will be licensed under the GPL-3.0-or-later license.

For major changes, please open an issue first to discuss what you would like to change. This ensures your time is well spent and increases the likelihood of your contribution being merged.

