// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

// Swapper for WETH, USDC, SSV
contract USDC_SSV_WETH_Swapper {
    address public weth;
    address public usdc;
    address public ssv;

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant FEE = 300; // 0.3%

    constructor(address _weth, address _usdc, address _ssv) {
        weth = _weth;
        usdc = _usdc;
        ssv = _ssv;
    }

    enum TokenType { WETH, USDC, SSV }

    function getTokenAddress(TokenType tokenType) internal view returns (address) {
        if (tokenType == TokenType.WETH) return weth;
        if (tokenType == TokenType.USDC) return usdc;
        if (tokenType == TokenType.SSV) return ssv;
        revert("Invalid token type");
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getSwapPrice(
        TokenType tokenIn,
        TokenType tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 price) {
        require(amountIn > 0, "Amount must be positive");
        require(tokenIn != tokenOut, "Cannot swap same token");

        uint256 balanceIn = IERC20(getTokenAddress(tokenIn)).balanceOf(address(this));
        uint256 balanceOut = IERC20(getTokenAddress(tokenOut)).balanceOf(address(this));
        require(balanceIn > 0 && balanceOut > 0, "Insufficient liquidity");

        amountOut = _getAmountOut(amountIn, balanceIn, balanceOut);
        price = (amountOut * 1e18) / amountIn;
    }

    function getReserves() external view returns (uint256 wethReserve, uint256 usdcReserve, uint256 ssvReserve) {
        wethReserve = IERC20(weth).balanceOf(address(this));
        usdcReserve = IERC20(usdc).balanceOf(address(this));
        ssvReserve = IERC20(ssv).balanceOf(address(this));
    }

    function swap(
        address recipient,
        TokenType tokenIn,
        TokenType tokenOut,
        uint256 amountIn
    ) external {
        require(amountIn > 0, "Amount must be positive");
        require(tokenIn != tokenOut, "Cannot swap same token");

        address tokenInAddress = getTokenAddress(tokenIn);
        address tokenOutAddress = getTokenAddress(tokenOut);

        uint256 amountOut = _getAmountOut(
            amountIn,
            IERC20(tokenInAddress).balanceOf(address(this)),
            IERC20(tokenOutAddress).balanceOf(address(this))
        );

        IERC20(tokenInAddress).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOutAddress).transfer(recipient, amountOut);
    }

    function withdrawTokens(address token, uint256 amount) external {
        IERC20(token).transfer(msg.sender, amount);
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}


