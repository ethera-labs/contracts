// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Vm} from "forge-std/Vm.sol";

/// @title ComposeConfig
/// @notice Reads shared L1 infrastructure config from config.json.
library ComposeConfig {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string private constant CONFIG_JSON = "config.json";

    function jsonContent() internal view returns (string memory) {
        return vm.readFile(CONFIG_JSON);
    }

    // ============ Deployment Configuration ============

    function guardian() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.guardian");
        require(addr != address(0), "ComposeConfig: guardian not set in config.json");
        return addr;
    }

    function proxyAdminOwner() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.proxyAdminOwner");
        require(addr != address(0), "ComposeConfig: proxyAdminOwner not set in config.json");
        return addr;
    }

    function depositWhitelistDefaultAdmin() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.depositWhitelistDefaultAdmin");
        require(addr != address(0), "ComposeConfig: depositWhitelistDefaultAdmin not set in config.json");
        return addr;
    }

    function depositWhitelistAdmin() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.depositWhitelistAdmin");
        require(addr != address(0), "ComposeConfig: depositWhitelistAdmin not set in config.json");
        return addr;
    }

    function authorizedProposer() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.authorizedProposer");
        require(addr != address(0), "ComposeConfig: authorizedProposer not set in config.json");
        return addr;
    }

    function sp1Verifier() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.sp1Verifier");
        require(addr != address(0), "ComposeConfig: sp1Verifier not set in config.json");
        return addr;
    }

    function aggregationVkey() internal view returns (bytes32) {
        bytes32 vkey = vm.parseJsonBytes32(jsonContent(), ".l1.aggregationVkey");
        require(vkey != bytes32(0), "ComposeConfig: aggregationVkey not set in config.json");
        return vkey;
    }

    function proofMaturityDelaySeconds() internal view returns (uint256) {
        try vm.parseJsonUint(jsonContent(), ".l1.proofMaturityDelaySeconds") returns (uint256 delay) {
            return delay;
        } catch {
            return 7 days;
        }
    }

    function disputeGameFinalityDelaySeconds() internal view returns (uint256) {
        try vm.parseJsonUint(jsonContent(), ".l1.disputeGameFinalityDelaySeconds") returns (uint256 delay) {
            return delay;
        } catch {
            return 3.5 days;
        }
    }

    function disputeGameInitBond() internal view returns (uint256) {
        try vm.parseJsonUint(jsonContent(), ".l1.disputeGameInitBond") returns (uint256 bond) {
            return bond;
        } catch {
            return 0.08 ether;
        }
    }

    // ============ Compose Deployment Addresses ============
    // Populated automatically by DeploySharedInfra when SAVE_DEPLOY_OUTPUT=true

    function proxyAdmin() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.proxyAdmin");
        require(addr != address(0), "ComposeConfig: proxyAdmin not set, run l1-deploy-shared first");
        return addr;
    }

    function superchainConfig() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.superchainConfig");
        require(addr != address(0), "ComposeConfig: superchainConfig not set, run l1-deploy-shared first");
        return addr;
    }

    function disputeGameFactory() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.disputeGameFactory");
        require(addr != address(0), "ComposeConfig: disputeGameFactory not set, run l1-deploy-shared first");
        return addr;
    }

    function anchorStateRegistry() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.anchorStateRegistry");
        require(addr != address(0), "ComposeConfig: anchorStateRegistry not set, run l1-deploy-shared first");
        return addr;
    }

    function ethLockbox() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.ethLockbox");
        require(addr != address(0), "ComposeConfig: ethLockbox not set, run l1-deploy-shared first");
        return addr;
    }

    function composeDisputeGame() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.composeDisputeGame");
        require(addr != address(0), "ComposeConfig: composeDisputeGame not set, run l1-deploy-shared first");
        return addr;
    }

    function erc20LockboxProxy() internal view returns (address) {
        try vm.parseJsonAddress(jsonContent(), ".l1.deployed.erc20LockboxProxy") returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }

    function depositWhitelist() internal view returns (address) {
        address addr = vm.parseJsonAddress(jsonContent(), ".l1.deployed.depositWhitelist");
        require(addr != address(0), "ComposeConfig: depositWhitelist not set, run l1-deploy-shared first");
        return addr;
    }

    function l1ChainId() internal view returns (uint256) {
        return vm.parseJsonUint(jsonContent(), ".l1.deployed.l1ChainId");
    }

    // ============ Validation ============

    function validateConfig() internal view {
        guardian();
        proxyAdminOwner();
        depositWhitelistDefaultAdmin();
        depositWhitelistAdmin();
        authorizedProposer();
        sp1Verifier();
        aggregationVkey();
    }
}
