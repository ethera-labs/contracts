// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Setup } from "@ssv/test/Setup.t.sol";
import { CetFactory } from "@ssv/src/bridge/CetFactory.sol";
import { ComposableERC20 } from "@ssv/src/bridge/ComposableErc20.sol";

contract CetFactoryTest is Setup {
    CetFactory internal factory;

    address internal l1Asset = address(0xBEEF);
    string internal name = "Token";
    string internal symbol = "TOK";
    uint8 internal decimals = 18;
    uint256 internal remoteChainId = 1;

    function setUp() public override {
        super.setUp();
        factory = new CetFactory();
        factory.setBridge(address(this));
    }

    function testComputeSalt() public {
        bytes32 expected = keccak256(abi.encode(l1Asset, remoteChainId));
        assertEq(factory.computeSalt(l1Asset, remoteChainId), expected);
    }

    function testPredictAddressMatchesCreate2() public {
        bytes32 salt = factory.computeSalt(l1Asset, remoteChainId);

        bytes memory ctorArgs = abi.encode(
            l1Asset,
            remoteChainId,
            name,
            symbol,
            decimals,
            address(this) // bridge is address(this) via setBridge
        );
        bytes memory bytecode = abi.encodePacked(
            type(ComposableERC20).creationCode,
            ctorArgs
        );
        bytes32 bytecodeHash = keccak256(bytecode);

        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            salt,
                            bytecodeHash
                        )
                    )
                )
            )
        );

        address predicted = factory.predictAddress(
            l1Asset,
            remoteChainId,
            decimals,
            name,
            symbol
        );

        assertEq(predicted, expected, "predict mismatch");
    }

    function testDeployIfAbsentDeploysComposableERC20() public {
        address predicted = factory.predictAddress(
            l1Asset,
            remoteChainId,
            decimals,
            name,
            symbol
        );

        address deployed = factory.deployIfAbsent(
            l1Asset,
            remoteChainId,
            decimals,
            name,
            symbol
        );

        assertEq(deployed, predicted, "wrong deployed address");
        assertGt(deployed.code.length, 0, "no contract code");
    }

    function testDeployIfAbsentReturnsSameAddressWhenAlreadyDeployed() public {
        address first = factory.deployIfAbsent(
            l1Asset,
            remoteChainId,
            decimals,
            name,
            symbol
        );

        address second = factory.deployIfAbsent(
            l1Asset,
            remoteChainId,
            decimals,
            name,
            symbol
        );

        assertEq(first, second, "should reuse existing deployment");
    }
}
