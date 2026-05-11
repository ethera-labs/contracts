// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";

import { SSVMintable } from "src/l2/dex/SSVMintable.sol";
import { USDCMintable } from "src/l2/dex/USDCMintable.sol";
import { WETH9 } from "@external/WETH9.sol";

/**
 * @title FundSwapper
 * @notice Script to fund the swapper with initial liquidity
 * @dev Mints tokens to the swapper address
 */
contract FundSwapper is Script {
    
    /**
     * @notice Main funding function
     * @param swapperAddress Address of the swapper contract
     * @param wethAddr Address of the WETH token
     * @param usdcAddr Address of the USDC token
     * @param ssvAddr Address of the SSV token
     * @param wethAmount Amount of WETH to mint (in wei)
     * @param usdcAmount Amount of USDC to mint (in wei, 18 decimals)
     * @param ssvAmount Amount of SSV to mint (in wei, 18 decimals)
     */
    function run(
        address swapperAddress,
        address wethAddr,
        address usdcAddr,
        address ssvAddr,
        uint256 wethAmount,
        uint256 usdcAmount,
        uint256 ssvAmount
    ) public {

        console.log("========================================");
        console.log("Funding Swapper with Liquidity");
        console.log("========================================");
        console.log("Swapper Address:", swapperAddress);
        console.log("========================================");
        console.log("Token Addresses:");
        console.log("  WETH:", wethAddr);
        console.log("  USDC:", usdcAddr);
        console.log("  SSV: ", ssvAddr);
        console.log("========================================");
        console.log("Amounts to Mint:");
        console.log("  WETH:", wethAmount);
        console.log("  USDC:", usdcAmount);
        console.log("  SSV: ", ssvAmount);
        console.log("========================================");

        vm.startBroadcast();
        console.log("ETH Balance for account 0x64F38Fe8EC155134DF973012ED8bb40f10D31F77:");
        console.log(address(0x64F38Fe8EC155134DF973012ED8bb40f10D31F77).balance);


        // Mint WETH to swapper
        // Note: WETH9 doesn't have a mint function, so we deposit ETH
        WETH9 weth = WETH9(payable(wethAddr));
        weth.deposit{value: wethAmount}();
        weth.transfer(swapperAddress, wethAmount);
        console.log("WETH deposited and transferred:", wethAmount);

        // Mint USDC to swapper
        USDCMintable usdc = USDCMintable(usdcAddr);
        usdc.mint(swapperAddress, usdcAmount);
        console.log("USDC minted:", usdcAmount);

        // Mint SSV to swapper
        SSVMintable ssv = SSVMintable(ssvAddr);
        ssv.mint(swapperAddress, ssvAmount);
        console.log("SSV minted:", ssvAmount);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("Swapper funded successfully!");
        console.log("========================================");
        
        // Display final balances
        console.log("Swapper Balances:");
        console.log("  WETH:", weth.balanceOf(swapperAddress));
        console.log("  USDC:", usdc.balanceOf(swapperAddress));
        console.log("  SSV: ", ssv.balanceOf(swapperAddress));
        console.log("========================================");
    }

    /**
     * @notice Helper function to fund with default amounts
     * @param swapperAddress Address of the swapper contract
     * @param wethAddr Address of the WETH token
     * @param usdcAddr Address of the USDC token
     * @param ssvAddr Address of the SSV token
     */
    function runDefault(
        address swapperAddress,
        address wethAddr,
        address usdcAddr,
        address ssvAddr
    ) public {
        // Default amounts: 1,000,000 of each token (1M * 10^18)
        uint256 defaultAmountETH = 100 ether;
        uint256 defaultAmountTokens = 1_000 ether;
        run(swapperAddress, wethAddr, usdcAddr, ssvAddr, defaultAmountETH, defaultAmountTokens, defaultAmountTokens);
    }
}
