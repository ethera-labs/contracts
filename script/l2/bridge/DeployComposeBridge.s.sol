// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";
import {CetFactory} from "src/l2/bridge/CETFactory.sol";
import {ComposeETHLiquidity} from "src/l2/bridge/ComposeETHLiquidity.sol";
import {UniversalBridgeMailbox} from "src/l2/bridge/UniversalBridgeMailbox.sol";
import {ComposeL2ToL2Bridge} from "src/l2/bridge/ComposeL2ToL2Bridge.sol";
import {L2ComposeBridge} from "src/l2/bridge/L2ComposeBridge.sol";

/// @title DeployComposeBridge
/// @notice One-shot L2 deploy + wiring for the Compose bridge stack.
///         Run once per L2. Three infra contracts (factory, mailbox, L2L2 bridge) use CREATE2 so
///         they land at the same address on every L2 — required for determinism of cross-chain
///         CET addresses and L2↔L2 message routing.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   owner                admin for factory / mailbox / ETHLiquidity / L2 bridge
///   coordinator          mailbox coordinator (off-chain relayer)
///   l1_chain_id          chain id of the L1 this rollup settles to
///   l2_xdm               L2 CrossDomainMessenger predeploy
///   create2_salt         bytes32 salt for cross-chain deterministic contracts
///   initial_eth_seed     optional — wei to fund ComposeETHLiquidity (0 = skip)
///
/// Env:
///   ROLLUP_NAME          selects section in rollups.toml
///   DEPLOYER_KEY         private key for broadcast
///   L1_COMPOSE_BRIDGE    optional — if set, wires L2Bridge.setOtherBridge
contract DeployComposeBridge is Script {
    CetFactory public cetFactory;
    ComposeETHLiquidity public ethLiquidity;
    UniversalBridgeMailbox public mailbox;
    ComposeL2ToL2Bridge public l2l2Bridge;
    L2ComposeBridge public l2Bridge;

    function run() external {
        address owner = RollupConfig.owner();
        address coordinator = RollupConfig.coordinator();
        uint256 l1ChainId = RollupConfig.l1ChainId();
        address l2Xdm = RollupConfig.l2Xdm();
        bytes32 salt = RollupConfig.create2Salt();
        uint256 initialSeed = RollupConfig.initialEthSeed();
        address l1Bridge = vm.envOr("L1_COMPOSE_BRIDGE", address(0));

        console.log("========================================");
        console.log("Deploy Compose Bridge (L2)");
        console.log("========================================");
        console.log("  chainid          :", block.chainid);
        console.log("  rollup           :", RollupConfig.rollupName());
        console.log("  owner            :", owner);
        console.log("  coordinator      :", coordinator);
        console.log("  l1ChainId        :", l1ChainId);
        console.log("  l2Xdm            :", l2Xdm);
        console.log("  l1ComposeBridge  :", l1Bridge);
        console.log("  initialEthSeed   :", initialSeed);

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        cetFactory = new CetFactory{salt: salt}(owner);
        console.log("\n[1a] CetFactory              :", address(cetFactory));

        mailbox = new UniversalBridgeMailbox{salt: salt}(coordinator, owner);
        console.log("[1b] UniversalBridgeMailbox   :", address(mailbox));

        ethLiquidity = new ComposeETHLiquidity{salt: salt}(owner);
        console.log("[1c] ComposeETHLiquidity      :", address(ethLiquidity));

        l2l2Bridge = new ComposeL2ToL2Bridge{salt: salt}(address(mailbox), address(cetFactory), address(ethLiquidity));
        console.log("[1d] ComposeL2ToL2Bridge      :", address(l2l2Bridge));

        l2Bridge = new L2ComposeBridge(l2Xdm, address(cetFactory), l1ChainId);
        console.log("\n[2]  L2ComposeBridge          :", address(l2Bridge));

        cetFactory.authorizeBridge(address(l2l2Bridge));
        cetFactory.authorizeBridge(address(l2Bridge));
        console.log("\n[3a] factory.authorizeBridge(L2L2, L2Compose) : ok");

        ethLiquidity.authorizeBridge(address(l2l2Bridge));
        console.log("[3b] ethLiquidity.authorizeBridge(L2L2)       : ok");

        mailbox.authorizeBridge(address(l2l2Bridge));
        console.log("[3c] mailbox.authorizeBridge(L2L2)            : ok");

        if (initialSeed > 0) {
            ethLiquidity.fund{value: initialSeed}();
            console.log("\n[4]  ethLiquidity.fund                        :", initialSeed);
        }

        if (l1Bridge != address(0)) {
            l2Bridge.setOtherBridge(l1Bridge);
            console.log("\n[5]  l2Bridge.setOtherBridge                  :", l1Bridge);
        } else {
            console.log("\n[5]  L1_COMPOSE_BRIDGE unset - run wire-bridge later.");
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("========================================");
    }
}
