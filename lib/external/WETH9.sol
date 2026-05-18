// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.30;

/// @title WETH9 (ported to solc 0.8.30)
/// @notice Same external ABI as canonical WETH9.
/// @dev Ported from 0.7.6 to 0.8.30 for unified compilation
contract WETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    error ERC20InsufficientBalance(
        address from,
        uint256 fromBalance,
        uint256 value
    );

    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);   

    receive() external payable {
        deposit();
    }

    fallback() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] = balanceOf[msg.sender] + msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "insufficient");
        balanceOf[msg.sender] = balanceOf[msg.sender] - wad;
        (bool ok, ) = msg.sender.call{ value: wad }("");
        require(ok, "ETH transfer failed");
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public returns (bool) {
        require(balanceOf[src] >= wad, "balance");
        if (
            src != msg.sender && allowance[src][msg.sender] != type(uint256).max
        ) {
            require(allowance[src][msg.sender] >= wad, "allowance");
            allowance[src][msg.sender] = allowance[src][msg.sender] - wad;
        }
        balanceOf[src] = balanceOf[src] - wad;
        balanceOf[dst] = balanceOf[dst] + wad;
        emit Transfer(src, dst, wad);
        return true;
    }

    function mint(address account, uint256 value) external {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        balanceOf[account] += value;
    }

    function burn(address account, uint256 value) external {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        balanceOf[account] -= value;
    }
}
