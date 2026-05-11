// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple mintable/burnable SSV (18 decimals) for testing
contract SSVMintable is ERC20 {
    constructor() ERC20("SSV Token", "SSV") {}

    function burn(address account, uint256 value) public {
        _burn(account, value);
    }

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}


