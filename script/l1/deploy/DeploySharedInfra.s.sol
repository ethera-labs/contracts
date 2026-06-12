// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {BaseDeployIO} from "./BaseDeployIO.sol";
import {ComposeDeployUtils} from "script/l1/libraries/ComposeDeployUtils.sol";
import {ComposeConfig} from "script/l1/libraries/ComposeConfig.sol";

// Interfaces
import {ISuperchainConfig} from "interfaces/L1/ISuperchainConfig.sol";
import {IDisputeGameFactory} from "interfaces/dispute/IDisputeGameFactory.sol";
import {IComposeAnchorStateRegistry} from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {IProxy} from "interfaces/universal/IProxy.sol";
import {IOptimismPortal2 as IOptimismPortal} from "interfaces/L1/IOptimismPortal2.sol";

// Types
import {GameType, Hash, Proposal} from "src/dispute/lib/Types.sol";

// Contracts
import {ProxyAdmin} from "src/universal/ProxyAdmin.sol";
import {Proxy} from "src/universal/Proxy.sol";
import {SuperchainConfig} from "src/L1/SuperchainConfig.sol";
import {DisputeGameFactory} from "src/dispute/DisputeGameFactory.sol";
import {ComposeAnchorStateRegistry} from "src/l1/ComposeAnchorStateRegistry.sol";
import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {ComposeETHLockbox} from "src/l1/ComposeETHLockbox.sol";
import {L1DepositWhitelist} from "src/l1/L1DepositWhitelist.sol";

/// @title DeploySharedInfraInput
/// @notice Input configuration for Phase 1: Deploy Shared Infrastructure
contract DeploySharedInfraInput is BaseDeployIO {
    // Governance addresses
    address internal _guardian;
    address internal _proxyAdminOwner;
    address internal _depositWhitelistDefaultAdmin;
    address internal _depositWhitelistAdmin;
    address internal _authorizedProposer;

    // Proof system
    address internal _sp1Verifier;
    bytes32 internal _aggregationVkey;

    // Delays and parameters
    uint256 internal _proofMaturityDelaySeconds;
    uint256 internal _disputeGameFinalityDelaySeconds;
    uint256 internal _disputeGameInitBond;

    // Setters
    function set(bytes4 sel, address val) public {
        require(val != address(0), "DeploySharedInfraInput: zero address");

        if (sel == this.guardian.selector) _guardian = val;
        else if (sel == this.proxyAdminOwner.selector) _proxyAdminOwner = val;
        else if (sel == this.depositWhitelistDefaultAdmin.selector) _depositWhitelistDefaultAdmin = val;
        else if (sel == this.depositWhitelistAdmin.selector) _depositWhitelistAdmin = val;
        else if (sel == this.authorizedProposer.selector) _authorizedProposer = val;
        else if (sel == this.sp1Verifier.selector) _sp1Verifier = val;
        else revert("DeploySharedInfraInput: unknown selector");
    }

    function set(bytes4 sel, bytes32 val) public {
        if (sel == this.aggregationVkey.selector) _aggregationVkey = val;
        else revert("DeploySharedInfraInput: unknown selector");
    }

    function set(bytes4 sel, uint256 val) public {
        if (sel == this.proofMaturityDelaySeconds.selector) _proofMaturityDelaySeconds = val;
        else if (sel == this.disputeGameFinalityDelaySeconds.selector) _disputeGameFinalityDelaySeconds = val;
        else if (sel == this.disputeGameInitBond.selector) _disputeGameInitBond = val;
        else revert("DeploySharedInfraInput: unknown selector");
    }

    // Getters
    function guardian() public view returns (address) {
        require(_guardian != address(0), "DeploySharedInfraInput: guardian not set");
        return _guardian;
    }

    function proxyAdminOwner() public view returns (address) {
        require(_proxyAdminOwner != address(0), "DeploySharedInfraInput: proxyAdminOwner not set");
        return _proxyAdminOwner;
    }

    function authorizedProposer() public view returns (address) {
        require(_authorizedProposer != address(0), "DeploySharedInfraInput: authorizedProposer not set");
        return _authorizedProposer;
    }

    function depositWhitelistDefaultAdmin() public view returns (address) {
        require(_depositWhitelistDefaultAdmin != address(0), "DeploySharedInfraInput: depositWhitelistDefaultAdmin not set");
        return _depositWhitelistDefaultAdmin;
    }

    function depositWhitelistAdmin() public view returns (address) {
        require(_depositWhitelistAdmin != address(0), "DeploySharedInfraInput: depositWhitelistAdmin not set");
        return _depositWhitelistAdmin;
    }

    function sp1Verifier() public view returns (address) {
        require(_sp1Verifier != address(0), "DeploySharedInfraInput: sp1Verifier not set");
        return _sp1Verifier;
    }

    function aggregationVkey() public view returns (bytes32) {
        require(_aggregationVkey != bytes32(0), "DeploySharedInfraInput: aggregationVkey not set");
        return _aggregationVkey;
    }

    function proofMaturityDelaySeconds() public view returns (uint256) {
        return _proofMaturityDelaySeconds;
    }

    function disputeGameFinalityDelaySeconds() public view returns (uint256) {
        return _disputeGameFinalityDelaySeconds;
    }

    function disputeGameInitBond() public view returns (uint256) {
        return _disputeGameInitBond; // Can be 0
    }
}

/// @title DeploySharedInfraOutput
/// @notice Output containing all deployed contract addresses
contract DeploySharedInfraOutput is BaseDeployIO {
    IProxyAdmin internal _composeProxyAdmin;
    ISuperchainConfig internal _composeSuperchainConfigImpl;
    ISuperchainConfig internal _composeSuperchainConfigProxy;
    IDisputeGameFactory internal _composeDisputeGameFactoryImpl;
    IDisputeGameFactory internal _composeDisputeGameFactoryProxy;
    IComposeAnchorStateRegistry internal _composeAnchorStateRegistryImpl;
    IComposeAnchorStateRegistry internal _composeAnchorStateRegistryProxy;
    ComposeETHLockbox internal _composeETHLockboxImpl;
    ComposeETHLockbox internal _composeETHLockboxProxy;
    L1DepositWhitelist internal _l1DepositWhitelistImpl;
    L1DepositWhitelist internal _l1DepositWhitelistProxy;
    ComposeDisputeGame internal _composeDisputeGameImpl;

    // Setters
    function set(bytes4 sel, address val) public {
        require(val != address(0), "DeploySharedInfraOutput: zero address");

        if (sel == this.composeProxyAdmin.selector) _composeProxyAdmin = IProxyAdmin(val);
        else if (sel == this.composeSuperchainConfigImpl.selector) _composeSuperchainConfigImpl = ISuperchainConfig(val);
        else if (sel == this.composeSuperchainConfigProxy.selector) _composeSuperchainConfigProxy = ISuperchainConfig(val);
        else if (sel == this.composeDisputeGameFactoryImpl.selector) _composeDisputeGameFactoryImpl = IDisputeGameFactory(val);
        else if (sel == this.composeDisputeGameFactoryProxy.selector) _composeDisputeGameFactoryProxy = IDisputeGameFactory(val);
        else if (sel == this.composeAnchorStateRegistryImpl.selector) _composeAnchorStateRegistryImpl = IComposeAnchorStateRegistry(val);
        else if (sel == this.composeAnchorStateRegistryProxy.selector) _composeAnchorStateRegistryProxy = IComposeAnchorStateRegistry(val);
        else if (sel == this.composeETHLockboxImpl.selector) _composeETHLockboxImpl = ComposeETHLockbox(payable(val));
        else if (sel == this.composeETHLockboxProxy.selector) _composeETHLockboxProxy = ComposeETHLockbox(payable(val));
        else if (sel == this.l1DepositWhitelistImpl.selector) _l1DepositWhitelistImpl = L1DepositWhitelist(val);
        else if (sel == this.l1DepositWhitelistProxy.selector) _l1DepositWhitelistProxy = L1DepositWhitelist(val);
        else if (sel == this.composeDisputeGameImpl.selector) _composeDisputeGameImpl = ComposeDisputeGame(val);
        else revert("DeploySharedInfraOutput: unknown selector");
    }

    // Getters
    function composeProxyAdmin() public view returns (IProxyAdmin) {
        require(address(_composeProxyAdmin) != address(0), "not set");
        return _composeProxyAdmin;
    }

    function composeSuperchainConfigImpl() public view returns (ISuperchainConfig) {
        require(address(_composeSuperchainConfigImpl) != address(0), "not set");
        return _composeSuperchainConfigImpl;
    }

    function composeSuperchainConfigProxy() public view returns (ISuperchainConfig) {
        require(address(_composeSuperchainConfigProxy) != address(0), "not set");
        return _composeSuperchainConfigProxy;
    }

    function composeDisputeGameFactoryImpl() public view returns (IDisputeGameFactory) {
        require(address(_composeDisputeGameFactoryImpl) != address(0), "not set");
        return _composeDisputeGameFactoryImpl;
    }

    function composeDisputeGameFactoryProxy() public view returns (IDisputeGameFactory) {
        require(address(_composeDisputeGameFactoryProxy) != address(0), "not set");
        return _composeDisputeGameFactoryProxy;
    }

    function composeAnchorStateRegistryImpl() public view returns (IComposeAnchorStateRegistry) {
        require(address(_composeAnchorStateRegistryImpl) != address(0), "not set");
        return _composeAnchorStateRegistryImpl;
    }

    function composeAnchorStateRegistryProxy() public view returns (IComposeAnchorStateRegistry) {
        require(address(_composeAnchorStateRegistryProxy) != address(0), "not set");
        return _composeAnchorStateRegistryProxy;
    }

    function composeETHLockboxImpl() public view returns (ComposeETHLockbox) {
        require(address(_composeETHLockboxImpl) != address(0), "not set");
        return _composeETHLockboxImpl;
    }

    function composeETHLockboxProxy() public view returns (ComposeETHLockbox) {
        require(address(_composeETHLockboxProxy) != address(0), "not set");
        return _composeETHLockboxProxy;
    }

    function l1DepositWhitelistImpl() public view returns (L1DepositWhitelist) {
        require(address(_l1DepositWhitelistImpl) != address(0), "not set");
        return _l1DepositWhitelistImpl;
    }

    function l1DepositWhitelistProxy() public view returns (L1DepositWhitelist) {
        require(address(_l1DepositWhitelistProxy) != address(0), "not set");
        return _l1DepositWhitelistProxy;
    }

    function composeDisputeGameImpl() public view returns (ComposeDisputeGame) {
        require(address(_composeDisputeGameImpl) != address(0), "not set");
        return _composeDisputeGameImpl;
    }
}

/// @title DeploySharedInfra
/// @notice Script to deploy Phase 1: Shared Infrastructure
/// @dev Deploys all cluster-wide contracts that will be shared across rollups
contract DeploySharedInfra is Script {
    // Compose Game Type
    uint32 public constant COMPOSE_GAME_TYPE = 5555;

    DeploySharedInfraInput public input;
    DeploySharedInfraOutput public output;

    /// @notice The entrypoint for the deployment script
    function run() public returns (DeploySharedInfraOutput) {
        return run(DeploySharedInfraInput(address(0)));
    }

    /// @notice The entrypoint with custom input
    function run(DeploySharedInfraInput _input) public returns (DeploySharedInfraOutput) {
        // Use provided input or load from environment
        if (address(_input) == address(0)) {
            input = loadInputFromEnvironment();
        } else {
            input = _input;
        }

        output = new DeploySharedInfraOutput();

        // Validate input
        assertValidInput();

        console.log("=================================================");
        console.log("Deploying Compose Shared Infrastructure (Phase 1)");
        console.log("=================================================");

        // Deploy in order
        deployProxyAdmin();
        deployBaseImplementations(); // Deploy everything except ComposeDisputeGame
        deployAndInitializeProxies();
        deployDisputeGameImplementation(); // Deploy ComposeDisputeGame with ASR proxy address
        registerDisputeGame();

        // Validate output
        assertValidOutput();

        console.log("=================================================");
        console.log("Phase 1 Deployment Complete!");
        console.log("=================================================");

        if (vm.envOr("SAVE_DEPLOY_OUTPUT", false)) {
            saveOutput();
        }

        return output;
    }

    /// @notice Write deployed addresses into config.json under l1.deployed.
    ///         Enabled by setting SAVE_DEPLOY_OUTPUT=true (not run during tests).
    function saveOutput() internal {
        string memory cfgPath = string.concat(vm.projectRoot(), "/config.json");

        vm.writeJson(vm.toString(address(output.composeProxyAdmin())), cfgPath, ".l1.deployed.proxyAdmin");
        vm.writeJson(vm.toString(address(output.composeSuperchainConfigProxy())), cfgPath, ".l1.deployed.superchainConfig");
        vm.writeJson(vm.toString(address(output.composeDisputeGameFactoryProxy())), cfgPath, ".l1.deployed.disputeGameFactory");
        vm.writeJson(vm.toString(address(output.composeAnchorStateRegistryProxy())), cfgPath, ".l1.deployed.anchorStateRegistry");
        vm.writeJson(vm.toString(address(output.composeETHLockboxProxy())), cfgPath, ".l1.deployed.ethLockbox");
        vm.writeJson(vm.toString(address(output.l1DepositWhitelistProxy())), cfgPath, ".l1.deployed.depositWhitelist");
        vm.writeJson(vm.toString(address(output.composeDisputeGameImpl())), cfgPath, ".l1.deployed.composeDisputeGame");
        vm.writeJson(vm.toString(block.chainid), cfgPath, ".l1.deployed.l1ChainId");

        console.log("Saved deploy output to config.json [l1.deployed]");
    }

    /// @notice Load input from config.json
    function loadInputFromEnvironment() internal returns (DeploySharedInfraInput) {
        DeploySharedInfraInput envInput = new DeploySharedInfraInput();

        // All required config values will revert if not set in config.json
        envInput.set(envInput.guardian.selector, ComposeConfig.guardian());
        envInput.set(envInput.proxyAdminOwner.selector, ComposeConfig.proxyAdminOwner());
        envInput.set(envInput.depositWhitelistDefaultAdmin.selector, ComposeConfig.depositWhitelistDefaultAdmin());
        envInput.set(envInput.depositWhitelistAdmin.selector, ComposeConfig.depositWhitelistAdmin());
        envInput.set(envInput.authorizedProposer.selector, ComposeConfig.authorizedProposer());
        envInput.set(envInput.sp1Verifier.selector, ComposeConfig.sp1Verifier());
        envInput.set(envInput.aggregationVkey.selector, ComposeConfig.aggregationVkey());

        // Optional config with sensible defaults
        envInput.set(envInput.proofMaturityDelaySeconds.selector, ComposeConfig.proofMaturityDelaySeconds());
        envInput.set(envInput.disputeGameFinalityDelaySeconds.selector, ComposeConfig.disputeGameFinalityDelaySeconds());
        envInput.set(envInput.disputeGameInitBond.selector, ComposeConfig.disputeGameInitBond());

        return envInput;
    }

    /// @notice Deploy the ProxyAdmin
    function deployProxyAdmin() internal {
        console.log("\n1. Deploying ProxyAdmin...");

        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        ProxyAdmin proxyAdmin = new ProxyAdmin(input.proxyAdminOwner());
        vm.stopBroadcast();

        ComposeDeployUtils.label(address(proxyAdmin), "ComposeProxyAdmin");
        console.log("  ProxyAdmin deployed at:", address(proxyAdmin));

        output.set(output.composeProxyAdmin.selector, address(proxyAdmin));
    }

    /// @notice Deploy base implementation contracts (without ComposeDisputeGame)
    function deployBaseImplementations() internal {
        console.log("\n2. Deploying Base Implementations...");

        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));

        // SuperchainConfig implementation
        SuperchainConfig superchainConfigImpl = new SuperchainConfig();
        ComposeDeployUtils.label(address(superchainConfigImpl), "ComposeSuperchainConfigImpl");
        console.log("  SuperchainConfig impl:", address(superchainConfigImpl));

        // DisputeGameFactory implementation
        DisputeGameFactory disputeGameFactoryImpl = new DisputeGameFactory();
        ComposeDeployUtils.label(address(disputeGameFactoryImpl), "ComposeDisputeGameFactoryImpl");
        console.log("  DisputeGameFactory impl:", address(disputeGameFactoryImpl));

        // AnchorStateRegistry implementation
        ComposeAnchorStateRegistry anchorStateRegistryImpl = new ComposeAnchorStateRegistry(input.disputeGameFinalityDelaySeconds());
        ComposeDeployUtils.label(address(anchorStateRegistryImpl), "ComposeAnchorStateRegistryImpl");
        console.log("  AnchorStateRegistry impl:", address(anchorStateRegistryImpl));

        // ETHLockbox implementation
        ComposeETHLockbox ethLockboxImpl = new ComposeETHLockbox();
        ComposeDeployUtils.label(address(ethLockboxImpl), "ComposeETHLockboxImpl");
        console.log("  ETHLockbox impl:", address(ethLockboxImpl));

        // L1DepositWhitelist implementation
        L1DepositWhitelist whitelistImpl = new L1DepositWhitelist();
        ComposeDeployUtils.label(address(whitelistImpl), "L1DepositWhitelistImpl");
        console.log("  L1DepositWhitelist impl:", address(whitelistImpl));

        vm.stopBroadcast();

        // Store addresses (off-chain)
        output.set(output.composeSuperchainConfigImpl.selector, address(superchainConfigImpl));
        output.set(output.composeDisputeGameFactoryImpl.selector, address(disputeGameFactoryImpl));
        output.set(output.composeAnchorStateRegistryImpl.selector, address(anchorStateRegistryImpl));
        output.set(output.composeETHLockboxImpl.selector, address(ethLockboxImpl));
        output.set(output.l1DepositWhitelistImpl.selector, address(whitelistImpl));
    }

    /// @notice Deploy and initialize all proxies
    function deployAndInitializeProxies() internal {
        console.log("\n3. Deploying and Initializing Proxies...");

        IProxyAdmin proxyAdmin = output.composeProxyAdmin();

        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));

        // SuperchainConfig Proxy
        Proxy superchainConfigProxy = new Proxy(address(proxyAdmin));
        proxyAdmin.upgradeAndCall(
            payable(address(superchainConfigProxy)),
            address(output.composeSuperchainConfigImpl()),
            abi.encodeCall(ISuperchainConfig.initialize, (input.guardian()))
        );
        ComposeDeployUtils.label(address(superchainConfigProxy), "ComposeSuperchainConfigProxy");
        console.log("  SuperchainConfig proxy:", address(superchainConfigProxy));

        // DisputeGameFactory Proxy
        Proxy disputeGameFactoryProxy = new Proxy(address(proxyAdmin));
        proxyAdmin.upgradeAndCall(
            payable(address(disputeGameFactoryProxy)),
            address(output.composeDisputeGameFactoryImpl()),
            abi.encodeCall(IDisputeGameFactory.initialize, (input.proxyAdminOwner())) // Temporary owner
        );
        ComposeDeployUtils.label(address(disputeGameFactoryProxy), "ComposeDisputeGameFactoryProxy");
        console.log("  DisputeGameFactory proxy:", address(disputeGameFactoryProxy));

        // AnchorStateRegistry Proxy
        Proxy anchorStateRegistryProxy = new Proxy(address(proxyAdmin));

        // Initialize with placeholder anchor root
        Proposal memory placeholderProposal = Proposal({root: Hash.wrap(bytes32(uint256(1))), l2SequenceNumber: 0});

        proxyAdmin.upgradeAndCall(
            payable(address(anchorStateRegistryProxy)),
            address(output.composeAnchorStateRegistryImpl()),
            abi.encodeCall(
                IComposeAnchorStateRegistry.initialize,
                (
                    ISuperchainConfig(address(superchainConfigProxy)),
                    IDisputeGameFactory(address(disputeGameFactoryProxy)),
                    placeholderProposal,
                    GameType.wrap(COMPOSE_GAME_TYPE)
                )
            )
        );
        ComposeDeployUtils.label(address(anchorStateRegistryProxy), "ComposeAnchorStateRegistryProxy");
        console.log("  AnchorStateRegistry proxy:", address(anchorStateRegistryProxy));

        // ETHLockbox Proxy
        Proxy ethLockboxProxy = new Proxy(address(proxyAdmin));

        // Initialize with empty portal list (will add portals during migration)
        IOptimismPortal[] memory emptyPortals = new IOptimismPortal[](0);
        proxyAdmin.upgradeAndCall(
            payable(address(ethLockboxProxy)),
            address(output.composeETHLockboxImpl()),
            abi.encodeCall(ComposeETHLockbox.initialize, (ISuperchainConfig(address(superchainConfigProxy)), emptyPortals))
        );
        ComposeDeployUtils.label(address(ethLockboxProxy), "ComposeETHLockboxProxy");
        console.log("  ETHLockbox proxy:", address(ethLockboxProxy));

        // L1DepositWhitelist Proxy
        Proxy whitelistProxy = new Proxy(address(proxyAdmin));
        proxyAdmin.upgradeAndCall(
            payable(address(whitelistProxy)),
            address(output.l1DepositWhitelistImpl()),
            abi.encodeCall(L1DepositWhitelist.initialize, (input.depositWhitelistDefaultAdmin(), input.depositWhitelistAdmin()))
        );
        ComposeDeployUtils.label(address(whitelistProxy), "L1DepositWhitelistProxy");
        console.log("  L1DepositWhitelist proxy:", address(whitelistProxy));

        vm.stopBroadcast();

        // Store addresses (off-chain)
        output.set(output.composeSuperchainConfigProxy.selector, address(superchainConfigProxy));
        output.set(output.composeDisputeGameFactoryProxy.selector, address(disputeGameFactoryProxy));
        output.set(output.composeAnchorStateRegistryProxy.selector, address(anchorStateRegistryProxy));
        output.set(output.composeETHLockboxProxy.selector, address(ethLockboxProxy));
        output.set(output.l1DepositWhitelistProxy.selector, address(whitelistProxy));
    }

    /// @notice Deploy ComposeDisputeGame implementation with ASR proxy address
    function deployDisputeGameImplementation() internal {
        console.log("\n4. Deploying ComposeDisputeGame Implementation...");

        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        ComposeDisputeGame disputeGameImpl =
            new ComposeDisputeGame(input.sp1Verifier(), input.aggregationVkey(), output.composeAnchorStateRegistryProxy(), input.authorizedProposer());
        ComposeDeployUtils.label(address(disputeGameImpl), "ComposeDisputeGameImpl");
        console.log("  ComposeDisputeGame impl:", address(disputeGameImpl));
        vm.stopBroadcast();

        // Store address (off-chain)
        output.set(output.composeDisputeGameImpl.selector, address(disputeGameImpl));
    }

    /// @notice Register ComposeDisputeGame in DisputeGameFactory
    function registerDisputeGame() internal {
        console.log("\n5. Registering ComposeDisputeGame...");

        IDisputeGameFactory dgf = output.composeDisputeGameFactoryProxy();
        IComposeAnchorStateRegistry asr = output.composeAnchorStateRegistryProxy();

        // Set game implementation and init bond (owner-only)
        vm.startBroadcast(vm.envOr("PROXY_ADMIN_OWNER_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        dgf.setImplementation(GameType.wrap(COMPOSE_GAME_TYPE), output.composeDisputeGameImpl());
        console.log("  Game type", COMPOSE_GAME_TYPE, "registered in DisputeGameFactory");

        if (input.disputeGameInitBond() > 0) {
            dgf.setInitBond(GameType.wrap(COMPOSE_GAME_TYPE), input.disputeGameInitBond());
            console.log("  Init bond set to:", input.disputeGameInitBond());
        }
        vm.stopBroadcast();

        // Set respected game type in AnchorStateRegistry (guardian-only)
        vm.startBroadcast(vm.envOr("GUARDIAN_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)));
        asr.setRespectedGameType(GameType.wrap(COMPOSE_GAME_TYPE));
        console.log("  Game type", COMPOSE_GAME_TYPE, "set as respected in AnchorStateRegistry");
        vm.stopBroadcast();
    }

    /// @notice Validate input configuration
    function assertValidInput() internal view {
        require(input.guardian() != address(0), "Guardian not set");
        require(input.proxyAdminOwner() != address(0), "ProxyAdmin owner not set");
        require(input.depositWhitelistDefaultAdmin() != address(0), "Deposit whitelist default admin not set");
        require(input.depositWhitelistAdmin() != address(0), "Deposit whitelist admin not set");
        require(input.authorizedProposer() != address(0), "Authorized proposer not set");
        require(input.sp1Verifier() != address(0), "SP1 verifier not set");
        require(input.aggregationVkey() != bytes32(0), "Aggregation vkey not set");
        console.log("\nInput Validation:");
        console.log("  Guardian:", input.guardian());
        console.log("  ProxyAdmin Owner:", input.proxyAdminOwner());
        console.log("  Deposit Whitelist Default Admin:", input.depositWhitelistDefaultAdmin());
        console.log("  Deposit Whitelist Admin:", input.depositWhitelistAdmin());
        console.log("  Authorized Proposer:", input.authorizedProposer());
        console.log("  SP1 Verifier:", input.sp1Verifier());
        console.log("  Aggregation Vkey:", vm.toString(input.aggregationVkey()));
        console.log("  Proof Maturity Delay:", input.proofMaturityDelaySeconds());
        console.log("  Dispute Game Finality Delay:", input.disputeGameFinalityDelaySeconds());
    }

    /// @notice Validate output deployment
    function assertValidOutput() internal view {
        // Check all contracts deployed
        require(address(output.composeProxyAdmin()) != address(0), "ProxyAdmin not deployed");
        require(address(output.composeSuperchainConfigImpl()) != address(0), "SuperchainConfig impl not deployed");
        require(address(output.composeSuperchainConfigProxy()) != address(0), "SuperchainConfig proxy not deployed");
        require(address(output.composeDisputeGameFactoryImpl()) != address(0), "DGF impl not deployed");
        require(address(output.composeDisputeGameFactoryProxy()) != address(0), "DGF proxy not deployed");
        require(address(output.composeAnchorStateRegistryImpl()) != address(0), "ASR impl not deployed");
        require(address(output.composeAnchorStateRegistryProxy()) != address(0), "ASR proxy not deployed");
        require(address(output.composeETHLockboxImpl()) != address(0), "Lockbox impl not deployed");
        require(address(output.composeETHLockboxProxy()) != address(0), "Lockbox proxy not deployed");
        require(address(output.l1DepositWhitelistImpl()) != address(0), "Whitelist impl not deployed");
        require(address(output.l1DepositWhitelistProxy()) != address(0), "Whitelist proxy not deployed");
        require(address(output.composeDisputeGameImpl()) != address(0), "DisputeGame impl not deployed");

        // Verify initialization
        ISuperchainConfig sc = output.composeSuperchainConfigProxy();
        require(sc.guardian() == input.guardian(), "Guardian mismatch");

        IComposeAnchorStateRegistry asr = output.composeAnchorStateRegistryProxy();
        require(address(asr.disputeGameFactory()) == address(output.composeDisputeGameFactoryProxy()), "ASR DGF mismatch");
        require(asr.respectedGameType().raw() == COMPOSE_GAME_TYPE, "ASR game type mismatch");

        ComposeETHLockbox lockbox = output.composeETHLockboxProxy();
        require(address(lockbox.superchainConfig()) == address(sc), "Lockbox SuperchainConfig mismatch");

        L1DepositWhitelist whitelist = output.l1DepositWhitelistProxy();
        require(whitelist.hasRole(whitelist.DEFAULT_ADMIN_ROLE(), input.depositWhitelistDefaultAdmin()), "Whitelist default admin mismatch");
        require(whitelist.hasRole(whitelist.DEPOSIT_WHITELIST_ROLE(), input.depositWhitelistAdmin()), "Whitelist admin mismatch");

        console.log("\nOutput Validation: All checks passed!");
    }
}
