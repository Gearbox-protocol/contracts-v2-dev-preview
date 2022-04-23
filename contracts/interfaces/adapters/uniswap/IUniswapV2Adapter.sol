// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {IUniswapV2Router02} from "../../../integrations/uniswap/IUniswapV2Router02.sol";
interface IUniswapV2Adapter is IAdapter, IUniswapV2Router02 {

    /// @dev Swap all assets into new one. Designed to simplify closure and liquidation process
    /// @param rateMinRAY minimum rate which is acceptable (in RAY format). amountOutMin = balance * rateMinRA / RAY
    /// @param path An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of
    ///        addresses must exist and have liquidity.
    /// @param deadline The same parameter as in Uniswap routers
    /// @return amounts result of Uniswap router swapExactTokensToTokens function
    function swapAllTokensForTokens(
        uint256 rateMinRAY,
        address[] calldata path,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
