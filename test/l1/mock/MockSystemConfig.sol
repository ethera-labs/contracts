// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IResourceMetering} from "interfaces/L1/IResourceMetering.sol";
import {ISystemConfig} from "interfaces/L1/ISystemConfig.sol";
import {ISuperchainConfig} from "interfaces/L1/ISuperchainConfig.sol";
import {Features} from "src/libraries/Features.sol";

/// @notice Minimal SystemConfig mock for ComposePortal integration tests. Returns safe defaults
///         for every method the portal touches during init + deposit/finalize paths.
contract MockSystemConfig {
    ISuperchainConfig public immutable _superchainConfig;
    address public immutable _guardian;
    uint256 public immutable _l2ChainId;

    bool public _paused;
    mapping(bytes32 => bool) public _features;

    constructor(ISuperchainConfig superchainConfig_, address guardian_, uint256 l2ChainId_) {
        _superchainConfig = superchainConfig_;
        _guardian = guardian_;
        _l2ChainId = l2ChainId_;
        // Enable the ETH_LOCKBOX feature by default — the portal requires it paired with a
        // non-zero `ethLockbox` storage slot.
        _features[Features.ETH_LOCKBOX] = true;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function setPaused(bool p) external {
        _paused = p;
    }

    function setFeature(bytes32 feature, bool enabled) external {
        _features[feature] = enabled;
    }

    function isFeatureEnabled(bytes32 feature) external view returns (bool) {
        return _features[feature];
    }

    function superchainConfig() external view returns (ISuperchainConfig) {
        return _superchainConfig;
    }

    function guardian() external view returns (address) {
        return _guardian;
    }

    function l2ChainId() external view returns (uint256) {
        return _l2ChainId;
    }

    function resourceConfig() external pure returns (IResourceMetering.ResourceConfig memory cfg_) {
        cfg_ = IResourceMetering.ResourceConfig({
            maxResourceLimit: 20_000_000,
            elasticityMultiplier: 10,
            baseFeeMaxChangeDenominator: 8,
            minimumBaseFee: 1 gwei,
            systemTxMaxGas: 1_000_000,
            maximumBaseFee: type(uint128).max
        });
    }
}
