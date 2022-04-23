// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma abicoder v1;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IstETH} from "../../integrations/lido/IstETH.sol";
import {IWETH} from "../../interfaces/external/IWETH.sol";

// EXCEPTIONS
import {ZeroAddressException} from "../../interfaces/IErrors.sol";

/// @title ConvexV1ClaimZapAdapter adapter
/// @dev Implements logic for claiming all tokens for creditAccount
contract LidoV1Gateway {
    // Original pool contract
    IstETH public immutable stETH;
    IWETH public immutable weth;

    /// @dev Constructor
    /// @param _weth WETH token address
    /// @param _stETH Address of staked ETH contract
    constructor(address _weth, address _stETH) {
        if (_weth == address(0) || _stETH == address(0))
            revert ZeroAddressException();

        stETH = IstETH(_stETH);
        weth = IWETH(_weth);
    }

    function submit(uint256 amount, address _referral)
        external
        returns (uint256 value)
    {
        IERC20(address(weth)).transferFrom(msg.sender, address(this), amount);
        weth.withdraw(amount);
        value = stETH.submit(_referral);
        stETH.transfer(msg.sender, stETH.balanceOf(address(this)));
    }
}
