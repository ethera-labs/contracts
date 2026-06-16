// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.18;

import {ComposableERC20} from "./ComposableERC20.sol";
import {ICETFactory} from "src/l2/interfaces/ICETFactory.sol";

/// @title CetFactory
/// @notice CREATE2 deployer for `ComposableERC20` wrapper tokens. The deployed address depends
///         ONLY on `(remoteAsset, remoteChainID)` — metadata is applied post-deploy so it
///         cannot shift the address.
contract CetFactory is ICETFactory {
    address public deployer;
    mapping(address => bool) public authorizedBridges;
    address[] public bridgeList;

    modifier onlyBridge() {
        if (!authorizedBridges[msg.sender]) revert OnlyBridge();
        _;
    }

    constructor() {}

    /// @notice One-shot post-deploy initializer. Must be called before authorizeBridge.
    function initialize(address _deployer) external {
        if (deployer != address(0)) revert AlreadyInitialized();
        if (_deployer == address(0)) revert ZeroAddress();
        deployer = _deployer;
    }

    function authorizeBridge(address _bridge) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (_bridge == address(0)) revert ZeroAddress();
        authorizedBridges[_bridge] = true;
        bridgeList.push(_bridge);
        emit BridgeAuthorized(_bridge);
    }

    function revokeBridge(address _bridge) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        authorizedBridges[_bridge] = false;
        emit BridgeRevoked(_bridge);
    }

    function computeSalt(address remoteAsset, uint256 remoteChainID) public pure returns (bytes32) {
        return keccak256(abi.encode(remoteAsset, remoteChainID));
    }

    function predictAddress(address remoteAsset, uint256 remoteChainID) public view returns (address) {
        bytes32 salt = computeSalt(remoteAsset, remoteChainID);

        bytes memory ctorArgs = abi.encode(remoteAsset, remoteChainID, address(this));
        bytes32 creationHash = keccak256(abi.encodePacked(type(ComposableERC20).creationCode, ctorArgs));

        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, creationHash)))));
    }

    function deployIfAbsent(address remoteAsset, uint256 remoteChainID, uint8 decimals_, string calldata name_, string calldata symbol_)
        external
        onlyBridge
        returns (address deployed)
    {
        address predicted = predictAddress(remoteAsset, remoteChainID);

        if (predicted.code.length > 0) {
            return predicted;
        }

        bytes32 salt = computeSalt(remoteAsset, remoteChainID);
        deployed = address(new ComposableERC20{salt: salt}(remoteAsset, remoteChainID, address(this)));
        require(deployed == predicted, "CetFactory: address mismatch");

        ComposableERC20(deployed).initializeMetadata(name_, symbol_, decimals_);
        _authorizeAllBridges(deployed);

        return deployed;
    }

    function _authorizeAllBridges(address cet) internal {
        ComposableERC20 token = ComposableERC20(cet);
        for (uint256 i; i < bridgeList.length; i++) {
            if (!token.authorizedBridges(bridgeList[i])) {
                token.authorizeBridge(bridgeList[i]);
            }
        }
    }
}
