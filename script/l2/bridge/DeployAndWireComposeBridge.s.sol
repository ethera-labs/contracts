// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";
import {CetFactory} from "src/l2/bridge/CETFactory.sol";
import {ComposeETHLiquidity} from "src/l2/bridge/ComposeETHLiquidity.sol";
import {UniversalBridgeMailbox} from "src/l2/bridge/UniversalBridgeMailbox.sol";
import {ComposeL2ToL2Bridge} from "src/l2/bridge/ComposeL2ToL2Bridge.sol";

/// @title DeployAndWireComposeBridge
/// @notice Deploy the L2↔L2 compose bridge stack in one shot. No L1 interaction.
///         All four contracts use CREATE2 so they land at the same address on every L2 —
///         required for cross-chain CET address determinism and message routing.
///
/// Config (rollups.toml via ROLLUP_NAME):
///   owner            admin for factory / mailbox / ETHLiquidity
///   coordinator      mailbox coordinator (off-chain relayer)
///   create2_salt     bytes32 salt — must be identical across all L2s in the mesh
///   initial_eth_seed optional — wei to fund ComposeETHLiquidity (0 = skip)
///
/// Env:
///   ROLLUP_NAME      selects section in rollups.toml
///   DEPLOYER_KEY     private key for broadcast
contract DeployAndWireComposeBridge is Script {
    CetFactory public cetFactory;
    ComposeETHLiquidity public ethLiquidity;
    UniversalBridgeMailbox public mailbox;
    ComposeL2ToL2Bridge public l2l2Bridge;

    function run() external {
        address owner = RollupConfig.owner();
        address coordinator = RollupConfig.coordinator();
        bytes32 salt = RollupConfig.create2Salt();
        uint256 initialSeed = RollupConfig.initialEthSeed();

        console.log("========================================");
        console.log("Deploy Compose L2-to-L2 Bridge Stack");
        console.log("========================================");
        console.log("  chainid     :", block.chainid);
        console.log("  rollup      :", RollupConfig.rollupName());
        console.log("  owner       :", owner);
        console.log("  coordinator :", coordinator);

        vm.startBroadcast(vm.envUint("DEPLOYER_KEY"));

        cetFactory = new CetFactory{salt: salt}(owner);
        mailbox = new UniversalBridgeMailbox{salt: salt}(coordinator, owner);
        ethLiquidity = new ComposeETHLiquidity{salt: salt}(owner);
        l2l2Bridge = new ComposeL2ToL2Bridge{salt: salt}(address(mailbox), address(cetFactory), address(ethLiquidity));

        console.log("\n[1] CetFactory             :", address(cetFactory));
        console.log("    UniversalBridgeMailbox  :", address(mailbox));
        console.log("    ComposeETHLiquidity     :", address(ethLiquidity));
        console.log("    ComposeL2ToL2Bridge     :", address(l2l2Bridge));

        cetFactory.authorizeBridge(address(l2l2Bridge));
        ethLiquidity.authorizeBridge(address(l2l2Bridge));
        mailbox.authorizeBridge(address(l2l2Bridge));
        console.log("\n[2] Authorizations wired");

        if (initialSeed > 0) {
            ethLiquidity.fund{value: initialSeed}();
            console.log("\n[3] ethLiquidity.fund      :", initialSeed);
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done - repeat on every L2 in the mesh");
        console.log("========================================");
    }
}
