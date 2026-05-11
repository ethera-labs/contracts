// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple mintable/burnable USDC (18 decimals) for testing
contract USDCMintable is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function burn(address account, uint256 value) public {
        _burn(account, value);
    }

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}


