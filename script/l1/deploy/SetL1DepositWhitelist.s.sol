// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {L1DepositWhitelist} from "src/l1/L1DepositWhitelist.sol";
import {ComposeConfig} from "script/l1/libraries/ComposeConfig.sol";
import {RollupConfig} from "script/l2/libraries/RollupConfig.sol";

/// @notice Operator helper for updating L1 deposit whitelist policy.
///
/// Env:
///   ROLLUP_NAME selects rollup in config.json
///   DEPOSIT_WHITELIST_ADMIN_KEY private key with DEPOSIT_WHITELIST_ROLE
contract SetL1DepositWhitelist is Script {
    function setPortalAllowed(bool allowed) external {
        address whitelist = ComposeConfig.depositWhitelist();
        address portal = RollupConfig.portalProxy();

        console.log("Set portal deposit whitelist");
        console.log("  rollup    :", RollupConfig.rollupName());
        console.log("  whitelist :", whitelist);
        console.log("  portal    :", portal);
        console.log("  allowed   :", allowed);

        vm.startBroadcast(vm.envUint("DEPOSIT_WHITELIST_ADMIN_KEY"));
        L1DepositWhitelist(whitelist).setPortalDepositAllowed(portal, allowed);
        vm.stopBroadcast();
    }

    function setERC20Allowed(address token, bool allowed) external {
        address whitelist = ComposeConfig.depositWhitelist();
        address portal = RollupConfig.portalProxy();
        require(token != address(0), "token=0");

        console.log("Set ERC20 deposit whitelist");
        console.log("  rollup    :", RollupConfig.rollupName());
        console.log("  whitelist :", whitelist);
        console.log("  portal    :", portal);
        console.log("  token     :", token);
        console.log("  allowed   :", allowed);

        vm.startBroadcast(vm.envUint("DEPOSIT_WHITELIST_ADMIN_KEY"));
        L1DepositWhitelist(whitelist).setERC20DepositAllowed(portal, token, allowed);
        vm.stopBroadcast();
    }
}
