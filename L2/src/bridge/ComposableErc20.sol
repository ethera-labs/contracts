// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC7802 } from "@openzeppelin/contracts/interfaces/draft-IERC7802.sol";
import { IComposableERC20 } from "@ssv/src/bridge/interfaces/IComposableERC20.sol";

contract ComposableERC20 is ERC20, IERC7802, IComposableERC20 {
    address public immutable override remoteAsset;
    uint256 public immutable override remoteChainID;
    uint8 public immutable tokenDecimals;

    address public bridge;

    constructor(
        address _remoteAsset,
        uint256 _remoteChainID,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _bridge
    ) ERC20(_name, _symbol) {
        remoteAsset = _remoteAsset;
        remoteChainID = _remoteChainID;
        tokenDecimals = _decimals;
        bridge = _bridge;
    }

    function crosschainMint(address to, uint256 amount) external override(IComposableERC20, IERC7802) {
        _onlyBridge();
        _mint(to, amount);
        emit CrosschainMint(to, amount, msg.sender);
    }

    function crosschainBurn(address from, uint256 amount) external override(IComposableERC20, IERC7802) {
        _onlyBridge();
        _burn(from, amount);
        emit CrosschainBurn(from, amount, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool){
        return interfaceId == type(IComposableERC20).interfaceId || interfaceId == type(IERC7802).interfaceId;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function _onlyBridge() internal view {
        if (msg.sender != bridge) {
            revert Unauthorized();
        }
    }
}