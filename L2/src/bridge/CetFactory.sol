// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { ComposableERC20 } from "@ssv/src/bridge/ComposableErc20.sol";
import { ICETFactory } from "@ssv/src/bridge/interfaces/ICetFactory.sol";

contract CetFactory is ICETFactory {
    address public bridge;
    address public immutable deployer;

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    constructor() {
        deployer = msg.sender;
    }

    function setBridge(address _bridge) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        if (bridge != address(0)) revert BridgeAlreadySet();
        if (_bridge == address(0)) revert ZeroAddress();
        bridge = _bridge;
    }

    function computeSalt(address remoteAsset, uint256 remoteChainID) public pure returns (bytes32){
        return keccak256(abi.encode(remoteAsset, remoteChainID));
    }

    function predictAddress(
        address remoteAsset,
        uint256 remoteChainID,
        uint8 decimals,
        string memory name,
        string memory symbol
    ) public view returns (address) {
        bytes32 salt = computeSalt(remoteAsset, remoteChainID);

        bytes memory ctorArgs = abi.encode(
            remoteAsset,
            remoteChainID,
            name,
            symbol,
            decimals,
            bridge
        );

        bytes32 creationHash = keccak256(
            abi.encodePacked(type(ComposableERC20).creationCode, ctorArgs)
        );

        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            creationHash
                        )
                    )
                )
            )
        );
    }

    function deployIfAbsent(
        address remoteAsset,
        uint256 remoteChainID,
        uint8 decimals,
        string calldata name,
        string calldata symbol
    ) external onlyBridge returns (address deployed) {
        bytes32 salt = computeSalt(remoteAsset, remoteChainID);

        address predicted = predictAddress(
            remoteAsset,
            remoteChainID,
            decimals,
            name,
            symbol
        );

        if (predicted.code.length > 0) {
            return predicted;
        }

        deployed = address(
            new ComposableERC20{salt: salt}(
                remoteAsset,
                remoteChainID,
                name,
                symbol,
                decimals,
                bridge
            )
        );

        require(deployed == predicted, "CetFactory: address mismatch");
        return deployed;
    }
}