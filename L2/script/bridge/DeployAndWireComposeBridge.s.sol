// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { CetFactory } from "@ssv/src/bridge/CETFactory.sol";
import { ComposeETHLiquidity } from "@ssv/src/bridge/ComposeETHLiquidity.sol";
import { UniversalBridgeMailbox } from "@ssv/src/bridge/UniversalBridgeMailbox.sol";
import { ComposeL2ToL2Bridge } from "@ssv/src/bridge/ComposeL2ToL2Bridge.sol";

/// @title DeployAndWireComposeBridge
/// @notice Deploy the L2↔L2 compose bridge stack in one shot. No L1 interaction.
///         All four contracts use CREATE2 so they land at the same address on every L2 —
///         required for cross-chain CET address determinism and message routing.
///
/// Env:
///   OWNER            admin for factory / mailbox / ETHLiquidity
///   COORDINATOR      mailbox coordinator (off-chain relayer)
///   CREATE2_SALT     bytes32 salt — must be identical across all L2s in the mesh
///   INITIAL_ETH_SEED optional — wei to fund ComposeETHLiquidity (0 = skip)
contract DeployAndWireComposeBridge is Script {
    CetFactory             public cetFactory;
    ComposeETHLiquidity    public ethLiquidity;
    UniversalBridgeMailbox public mailbox;
    ComposeL2ToL2Bridge    public l2l2Bridge;

    function run() external {
        address owner       = vm.envAddress("OWNER");
        address coordinator = vm.envAddress("COORDINATOR");
        bytes32 salt        = vm.envBytes32("CREATE2_SALT");
        uint256 initialSeed = vm.envOr("INITIAL_ETH_SEED", uint256(0));

        console.log("========================================");
        console.log("Deploy Compose L2-to-L2 Bridge Stack");
        console.log("========================================");
        console.log("  chainid     :", block.chainid);
        console.log("  owner       :", owner);
        console.log("  coordinator :", coordinator);

        vm.startBroadcast(owner);

        // -----------------------------------------------------------------------------------------
        // [1] Deploy via CREATE2 — same salt + same ctor args on every L2 = identical addresses
        // -----------------------------------------------------------------------------------------
        cetFactory   = new CetFactory{ salt: salt }(owner);
        mailbox      = new UniversalBridgeMailbox{ salt: salt }(coordinator, owner);
        ethLiquidity = new ComposeETHLiquidity{ salt: salt }(owner);
        l2l2Bridge   = new ComposeL2ToL2Bridge{ salt: salt }(
            address(mailbox),
            address(cetFactory),
            address(ethLiquidity)
        );

        console.log("\n[1] CetFactory             :", address(cetFactory));
        console.log("    UniversalBridgeMailbox  :", address(mailbox));
        console.log("    ComposeETHLiquidity     :", address(ethLiquidity));
        console.log("    ComposeL2ToL2Bridge     :", address(l2l2Bridge));

        // -----------------------------------------------------------------------------------------
        // [2] Authorizations
        // -----------------------------------------------------------------------------------------
        cetFactory.authorizeBridge(address(l2l2Bridge));
        ethLiquidity.authorizeBridge(address(l2l2Bridge));
        mailbox.authorizeBridge(address(l2l2Bridge));
        console.log("\n[2] Authorizations wired");

        // -----------------------------------------------------------------------------------------
        // [3] Optional: seed ETHLiquidity
        // -----------------------------------------------------------------------------------------
        if (initialSeed > 0) {
            ethLiquidity.fund{ value: initialSeed }();
            console.log("\n[3] ethLiquidity.fund      :", initialSeed);
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done - repeat on every L2 in the mesh");
        console.log("========================================");
    }
}
