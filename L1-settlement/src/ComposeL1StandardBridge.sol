// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { L1StandardBridge } from "@optimism/src/L1/L1StandardBridge.sol";
import { StandardBridge } from "@optimism/src/universal/StandardBridge.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOptimismMintableERC20 } from "@optimism/interfaces/universal/IOptimismMintableERC20.sol";
import { IComposeERC20Lockbox } from "src/interfaces/IComposeERC20Lockbox.sol";

/// @custom:proxied true
/// @title ComposeL1StandardBridge
/// @notice Extends L1StandardBridge to escrow non-mintable ERC20 tokens into a shared ComposeERC20Lockbox
///         instead of holding them in the bridge contract itself. This enables cross-rollup ERC20 withdrawals:
///         tokens deposited via Rollup A's bridge can be withdrawn via Rollup B's bridge, because both
///         bridges share the same lockbox.
///
///         Only the ERC20 escrow path is changed. OptimismMintableERC20 tokens (burn/mint pattern) and
///         ETH bridging are completely unchanged from the standard L1StandardBridge.
contract ComposeL1StandardBridge is L1StandardBridge {
    using SafeERC20 for IERC20;

    /// @notice Thrown when msg.value is non-zero on an ERC20 bridge call.
    error ComposeBridge_CannotSendValue();

    /// @notice Thrown when the remote token does not match the OptimismMintableERC20 pair.
    error ComposeBridge_WrongRemoteToken();

    /// @notice Thrown when the bridge is paused.
    error ComposeBridge_Paused();

    /// @notice The shared ERC20 lockbox that holds escrowed tokens across all Compose bridges.
    IComposeERC20Lockbox public erc20Lockbox;

    /// @notice Emitted when the ERC20 lockbox is set.
    /// @param lockbox The address of the ERC20 lockbox.
    event ERC20LockboxSet(address indexed lockbox);

    /// @notice Sets the shared ERC20 lockbox. Only callable by the ProxyAdmin owner.
    /// @param _lockbox The ComposeERC20Lockbox contract.
    function setERC20Lockbox(IComposeERC20Lockbox _lockbox) external {
        _assertOnlyProxyAdminOwner();
        erc20Lockbox = _lockbox;
        emit ERC20LockboxSet(address(_lockbox));
    }

    /// @notice Override to escrow non-mintable ERC20 tokens into the shared lockbox instead of
    ///         holding them in this bridge contract. Mintable tokens still use burn/mint.
    /// @dev    For non-mintable tokens the lockbox pulls directly from the user in a single transfer.
    ///         The user must approve the lockbox (not the bridge) for the token amount.
    ///         Deposit accounting is tracked in the lockbox via `totalDeposited`, not in the bridge's
    ///         `deposits` mapping, since liquidity is shared across all bridges.
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
        override
    {
        if (msg.value != 0) {
            revert ComposeBridge_CannotSendValue();
        }

        if (_isOptimismMintableERC20(_localToken)) {
            if (!_isCorrectTokenPair(_localToken, _remoteToken)) {
                revert ComposeBridge_WrongRemoteToken();
            }

            IOptimismMintableERC20(_localToken).burn(_from, _amount);
        } else {
            erc20Lockbox.lockERC20(_localToken, _from, _amount);
        }

        _emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(
                this.finalizeBridgeERC20.selector,
                _remoteToken,
                _localToken,
                _from,
                _to,
                _amount,
                _extraData
            ),
            _minGasLimit: _minGasLimit
        });
    }

    /// @notice Override to release non-mintable ERC20 tokens from the shared lockbox instead of
    ///         from this bridge's own balance. Mintable tokens still use mint.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        override
        onlyOtherBridge
    {
        if (paused()) {
            revert ComposeBridge_Paused();
        }

        if (_isOptimismMintableERC20(_localToken)) {
            if (!_isCorrectTokenPair(_localToken, _remoteToken)) {
                revert ComposeBridge_WrongRemoteToken();
            }

            IOptimismMintableERC20(_localToken).mint(_to, _amount);
        } else {
            erc20Lockbox.unlockERC20(_localToken, _amount, _to);
        }

        _emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
