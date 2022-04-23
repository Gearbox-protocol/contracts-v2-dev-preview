// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {ISwapRouter} from "../../../integrations/uniswap/IUniswapV3.sol";


interface IUniswapV3AdapterExceptions {
    error IncorrectPathLengthException();
}

interface IUniswapV3Adapter is IAdapter, ISwapRouter, IUniswapV3AdapterExceptions {
    
    struct ExactAllInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 deadline;
        uint256 rateMinRAY;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactAllInputSingle(ExactAllInputSingleParams calldata params)
        external
        returns (uint256 amountOut);

    struct ExactAllInputParams {
        bytes path;
        uint256 deadline;
        uint256 rateMinRAY;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactAllInput(ExactAllInputParams calldata params)
        external
        returns (uint256 amountOut);
}
