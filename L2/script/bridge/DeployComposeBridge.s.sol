// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { CetFactory } from "@ssv/src/bridge/CETFactory.sol";
import { ComposeETHLiquidity } from "@ssv/src/bridge/ComposeETHLiquidity.sol";
import { UniversalBridgeMailbox } from "@ssv/src/bridge/UniversalBridgeMailbox.sol";
import { ComposeL2ToL2Bridge } from "@ssv/src/bridge/ComposeL2ToL2Bridge.sol";
import { L2ComposeBridge } from "@ssv/src/bridge/L2ComposeBridge.sol";

/// @title DeployComposeBridge
/// @notice One-shot L2 deploy + wiring for the Compose bridge stack.
///         Run once per L2. Three infra contracts (factory, mailbox, L2L2 bridge) use CREATE2 so
///         they land at the same address on every L2 — required for determinism of cross-chain
///         CET addresses and L2↔L2 message routing.
///
/// Env:
///   OWNER                 admin for factory / mailbox / ETHLiquidity / L2 bridge
///   COORDINATOR           mailbox coordinator (off-chain relayer)
///   L1_CHAIN_ID           chain id of the L1 this rollup settles to
///   L2_XDM                L2 CrossDomainMessenger predeploy (usually 0x4200000000000000000000000000000000000007)
///   L1_COMPOSE_BRIDGE     optional — if 0, skip setOtherBridge (call later)
///   INITIAL_ETH_SEED      optional — wei to fund ComposeETHLiquidity (0 = skip)
///   CREATE2_SALT          bytes32 salt used for the three cross-chain contracts
contract DeployComposeBridge is Script {
    // Deployed
    CetFactory           public cetFactory;
    ComposeETHLiquidity  public ethLiquidity;
    UniversalBridgeMailbox public mailbox;
    ComposeL2ToL2Bridge  public l2l2Bridge;
    L2ComposeBridge      public l2Bridge;

    function run() external {
        address owner            = vm.envAddress("OWNER");
        address coordinator      = vm.envAddress("COORDINATOR");
        uint256 l1ChainId        = vm.envUint("L1_CHAIN_ID");
        address l2Xdm            = vm.envAddress("L2_XDM");
        address l1Bridge         = vm.envOr("L1_COMPOSE_BRIDGE", address(0));
        uint256 initialSeed      = vm.envOr("INITIAL_ETH_SEED", uint256(0));
        bytes32 salt             = vm.envBytes32("CREATE2_SALT");

        console.log("========================================");
        console.log("Deploy Compose Bridge (L2)");
        console.log("========================================");
        console.log("  chainid          :", block.chainid);
        console.log("  owner            :", owner);
        console.log("  coordinator      :", coordinator);
        console.log("  l1ChainId        :", l1ChainId);
        console.log("  l2Xdm            :", l2Xdm);
        console.log("  l1ComposeBridge  :", l1Bridge);
        console.log("  initialEthSeed   :", initialSeed);

        vm.startBroadcast(owner);

        // -----------------------------------------------------------------------------------------
        // [1] Cross-chain-deterministic contracts via CREATE2
        // -----------------------------------------------------------------------------------------
        // (a) CetFactory — salt only. No ctor args.
        cetFactory = new CetFactory{ salt: salt }();
        console.log("\n[1a] CetFactory              :", address(cetFactory));

        // (b) UniversalBridgeMailbox — ctor(coordinator). Coordinator must be SAME value across
        //      all chains that will route L2↔L2 mail, so the mailbox address is identical.
        mailbox = new UniversalBridgeMailbox{ salt: salt }(coordinator);
        console.log("[1b] UniversalBridgeMailbox   :", address(mailbox));

        // (c) ComposeETHLiquidity — chain-local pool. Address parity across chains not required
        //      for correctness (bridge just holds a reference). CREATE2 for consistency.
        ethLiquidity = new ComposeETHLiquidity{ salt: salt }(owner);
        console.log("[1c] ComposeETHLiquidity      :", address(ethLiquidity));

        // (d) ComposeL2ToL2Bridge — ctor(mailbox, factory, ethLiquidity). To keep the address
        //      identical across chains, mailbox & factory must be at same addr cross-chain AND
        //      ethLiquidity must be the same address cross-chain. (c) is deployed via CREATE2
        //      with matching salt so this holds when owner is a known EOA or deterministic deployer.
        l2l2Bridge = new ComposeL2ToL2Bridge{ salt: salt }(
            address(mailbox),
            address(cetFactory),
            address(ethLiquidity)
        );
        console.log("[1d] ComposeL2ToL2Bridge      :", address(l2l2Bridge));

        // -----------------------------------------------------------------------------------------
        // [2] Per-rollup: L2ComposeBridge. Regular `new` — address differs per rollup, fine.
        // -----------------------------------------------------------------------------------------
        l2Bridge = new L2ComposeBridge(l2Xdm, address(cetFactory), l1ChainId);
        console.log("\n[2]  L2ComposeBridge          :", address(l2Bridge));

        // -----------------------------------------------------------------------------------------
        // [3] Wire authorizations
        // -----------------------------------------------------------------------------------------
        // (a) Factory must know BOTH bridges before any CET gets deployed, so every future CET
        //      auto-authorizes both via _authorizeAllBridges.
        cetFactory.authorizeBridge(address(l2l2Bridge));
        cetFactory.authorizeBridge(address(l2Bridge));
        console.log("\n[3a] factory.authorizeBridge(L2L2, L2Compose) : ok");

        // (b) ETHLiquidity: L2↔L2 bridge only. L2ComposeBridge doesn't touch ETHLiquidity
        //      (L1↔L2 ETH flows through the portal's ETHLockbox on L1).
        ethLiquidity.authorizeBridge(address(l2l2Bridge));
        console.log("[3b] ethLiquidity.authorizeBridge(L2L2)       : ok");

        // (c) Mailbox: L2↔L2 bridge only. L2ComposeBridge doesn't use the mailbox.
        mailbox.authorizeBridge(address(l2l2Bridge));
        console.log("[3c] mailbox.authorizeBridge(L2L2)            : ok");

        // -----------------------------------------------------------------------------------------
        // [4] Optional: seed ETHLiquidity
        // -----------------------------------------------------------------------------------------
        if (initialSeed > 0) {
            ethLiquidity.fund{ value: initialSeed }();
            console.log("\n[4]  ethLiquidity.fund                        :", initialSeed);
        }

        // -----------------------------------------------------------------------------------------
        // [5] Optional: wire L1 counterparty if known
        // -----------------------------------------------------------------------------------------
        if (l1Bridge != address(0)) {
            l2Bridge.setOtherBridge(l1Bridge);
            console.log("\n[5]  l2Bridge.setOtherBridge                  :", l1Bridge);
        } else {
            console.log("\n[5]  L1_COMPOSE_BRIDGE unset - run setOtherBridge later.");
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("Done");
        console.log("========================================");
    }
}
