// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Proxy} from "src/universal/Proxy.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";
import {ComposeAnchorStateRegistry} from "src/l1/ComposeAnchorStateRegistry.sol";
import {ComposeDisputeGame} from "src/l1/ComposeDisputeGame.sol";
import {IComposeAnchorStateRegistry} from "src/l1/interfaces/IComposeAnchorStateRegistry.sol";

import {ISuperchainConfig} from "interfaces/L1/ISuperchainConfig.sol";
import {IDisputeGameFactory} from "interfaces/dispute/IDisputeGameFactory.sol";
import {GameType, Proposal, Hash} from "@optimism/src/dispute/lib/Types.sol";

/// @title DeployASRAndRegisterGame
/// @notice Retrofits an existing Compose deployment that was built on L2OutputOracle to the
///         current ASR-based architecture. Keeps existing SuperchainConfig, DGF, Lockboxes.
///         Deploys: ComposeAnchorStateRegistry (proxy + impl) and a fresh ComposeDisputeGame
///         impl wired to the new ASR. Registers the new impl in the existing DGF.
///
/// Env:
///   PROXY_ADMIN            existing ComposeProxyAdmin
///   PROXY_ADMIN_OWNER      owner of ProxyAdmin (signs ASR proxy init)
///   DGF_OWNER              owner of DisputeGameFactory (signs setImplementation)
///   SUPERCHAIN_CONFIG      existing SuperchainConfig proxy
///   DISPUTE_GAME_FACTORY   existing DGF proxy
///   SP1_VERIFIER           SP1 verifier contract on this L1
///   AGGREGATION_VKEY       bytes32 SP1 aggregation verifying key
///   AUTHORIZED_PROPOSER    EOA that will create games
///   DG_FINALITY_DELAY      dispute game finality delay in seconds (ASR constructor)
///   DG_INIT_BOND           optional init bond (wei); 0 = skip
contract DeployASRAndRegisterGame is Script {
    uint32 public constant COMPOSE_GAME_TYPE = 5555;

    function run() external returns (address asrProxyAddr, address asrImplAddr, address newGameImplAddr) {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        address dgfOwner = vm.envAddress("DGF_OWNER");
        address superchainConfig = vm.envAddress("SUPERCHAIN_CONFIG");
        address dgf = vm.envAddress("DISPUTE_GAME_FACTORY");
        address sp1Verifier = vm.envAddress("SP1_VERIFIER");
        bytes32 aggregationVkey = vm.envBytes32("AGGREGATION_VKEY");
        address proposer = vm.envAddress("AUTHORIZED_PROPOSER");
        uint256 initBond = vm.envOr("DG_INIT_BOND", uint256(0));
        uint256 dgFinalityDelay = vm.envUint("DG_FINALITY_DELAY");

        vm.rememberKey(vm.envUint("PK_ADMIN"));
        vm.rememberKey(vm.envUint("PK_DGF_OWNER"));

        vm.startBroadcast(proxyAdminOwner);
        ComposeAnchorStateRegistry asrImpl = new ComposeAnchorStateRegistry(dgFinalityDelay);
        asrImplAddr = address(asrImpl);
        console.log("\n[1a] ASR impl              :", asrImplAddr);

        Proxy asrProxy = new Proxy(proxyAdmin);
        asrProxyAddr = address(asrProxy);
        console.log("[1b] ASR proxy             :", asrProxyAddr);

        Proposal memory placeholder = Proposal({root: Hash.wrap(bytes32(uint256(1))), l2SequenceNumber: 0});

        IProxyAdmin(proxyAdmin)
            .upgradeAndCall(
                payable(asrProxyAddr),
                asrImplAddr,
                abi.encodeCall(
                    IComposeAnchorStateRegistry.initialize,
                    (ISuperchainConfig(superchainConfig), IDisputeGameFactory(dgf), placeholder, GameType.wrap(COMPOSE_GAME_TYPE))
                )
            );
        console.log("[1c] ASR initialized (respectedGameType = 5555)");

        ComposeDisputeGame gameImpl = new ComposeDisputeGame(sp1Verifier, aggregationVkey, IComposeAnchorStateRegistry(asrProxyAddr), proposer);
        newGameImplAddr = address(gameImpl);
        console.log("\n[2]  new ComposeDisputeGame impl :", newGameImplAddr);

        vm.stopBroadcast();

        vm.startBroadcast(dgfOwner);

        IDisputeGameFactory(dgf).setImplementation(GameType.wrap(COMPOSE_GAME_TYPE), gameImpl);
        console.log("\n[3]  DGF.setImplementation(5555, new) : ok");

        if (initBond > 0) {
            IDisputeGameFactory(dgf).setInitBond(GameType.wrap(COMPOSE_GAME_TYPE), initBond);
            console.log("[3b] DGF.setInitBond                  :", initBond);
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("  ASR proxy             :", asrProxyAddr);
        console.log("  new DisputeGame impl  :", newGameImplAddr);
        console.log("  NEXT: repoint proposer to new DisputeGame impl");
        console.log("========================================");
    }
}
