// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISuperchainConfig} from "interfaces/L1/ISuperchainConfig.sol";
import {IProxyAdmin} from "interfaces/universal/IProxyAdmin.sol";

contract MockSuperchainConfig is ISuperchainConfig {
    bool internal globalPause;
    mapping(address => bool) internal localPause;
    address internal _l2Sender;

    function __constructor__() external override {}

    function paused(address _identifier) external view override returns (bool) {
        return globalPause || localPause[_identifier];
    }

    function paused() external view override returns (bool) {
        return globalPause;
    }

    function pause(address _identifier) external override {
        if (_identifier == address(0)) globalPause = true;
        else localPause[_identifier] = true;
    }

    function unpause(address _identifier) external override {
        if (_identifier == address(0)) globalPause = false;
        else localPause[_identifier] = false;
    }

    function expiration(address) external pure override returns (uint256) {
        return 0;
    }

    function extend(address) external override {}

    function initVersion() external pure override returns (uint8) {
        return 1;
    }

    function version() external pure override returns (string memory) {
        return "mock";
    }

    function guardian() external pure override returns (address) {
        return address(0x1234);
    }

    function initialize(address) external override {}

    function proxyAdmin() external pure override returns (IProxyAdmin) {
        return IProxyAdmin(address(0));
    }

    function proxyAdminOwner() external pure override returns (address) {
        return address(0);
    }

    function upgrade() external override {}

    function pauseTimestamps(address) external pure override returns (uint256) {
        return 0;
    }

    function pauseExpiry() external pure override returns (uint256) {
        return 0;
    }

    function pausable(address) external pure override returns (bool) {
        return true;
    }
}
