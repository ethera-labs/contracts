// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ISP1Verifier} from "@sp1-contracts/src/ISP1Verifier.sol";

contract SP1MockVerifier is ISP1Verifier {
    function verifyProof(bytes32, bytes calldata, bytes calldata) external pure override {}
}
