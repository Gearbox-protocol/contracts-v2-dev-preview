// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {IUniswapV3Adapter} from "../../interfaces/adapters/uniswap/IUniswapV3Adapter.sol";
import {AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ISwapRouter} from "../../integrations/uniswap/IUniswapV3.sol";
import {BytesLib} from "../../integrations/uniswap/BytesLib.sol";

import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

/// @dev The length of the bytes encoded address
uint256 constant ADDR_SIZE = 20;

/// @dev The length of the uint24 encoded address
uint256 constant FEE_SIZE = 3;

uint256 constant MIN_PATH_LENGTH = 2 * ADDR_SIZE + FEE_SIZE;

uint256 constant ADDR_PLUS_FEE_LENGTH = ADDR_SIZE + FEE_SIZE;

/// @title UniswapV3 Router adapter
contract UniswapV3Adapter is
    AbstractAdapter,
    IUniswapV3Adapter,
    ReentrancyGuard
{
    using BytesLib for bytes;

    AdapterType public constant _gearboxAdapterType = AdapterType.UNISWAP_V3;
    uint16 public constant _gearboxAdapterVersion = 2;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _router Address of ISwapRouter
    constructor(address _creditManager, address _router)
        AbstractAdapter(_creditManager, _router)
    {}

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        ExactInputSingleParams memory paramsUpdate = params; // F:[AUV3-4,10]
        paramsUpdate.recipient = creditAccount; // F:[AUV3-4,10]

        amountOut = abi.decode(
            _executeFastCheck(
                creditAccount,
                params.tokenIn,
                params.tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactInputSingle.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV2-5,9,10]
    }

    function exactAllInputSingle(ExactAllInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        uint256 balanceInBefore = IERC20(params.tokenIn).balanceOf(
            creditAccount
        ); // F:[AUV3-8,14]

        ExactInputSingleParams memory paramsUpdate = ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: creditAccount,
            deadline: params.deadline,
            amountIn: balanceInBefore - 1,
            amountOutMinimum: ((balanceInBefore - 1) * params.rateMinRAY) / RAY,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        }); // F:[AUV3-8,14]

        amountOut = abi.decode(
            _executeFastCheck(
                creditAccount,
                params.tokenIn,
                params.tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactInputSingle.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV3-8,14]
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        (address tokenIn, address tokenOut) = _extractTokens(params.path); // F:[AUV3-6,12]

        ExactInputParams memory paramsUpdate = params; // F:[AUV3-6,12]
        paramsUpdate.recipient = creditAccount; // F:[AUV3-6,12]

        amountOut = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactInput.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV3-6,12]
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactAllInput(ExactAllInputParams calldata params)
        external
        returns (uint256 amountOut)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        (address tokenIn, address tokenOut) = _extractTokens(params.path); // F:[AUV3-9,15]

        uint256 balanceInBefore = IERC20(tokenIn).balanceOf(creditAccount); // F:[AUV3-9,15]

        ExactInputParams memory paramsUpdate = ExactInputParams({
            path: params.path,
            recipient: creditAccount,
            deadline: params.deadline,
            amountIn: balanceInBefore - 1,
            amountOutMinimum: ((balanceInBefore - 1) * params.rateMinRAY) / RAY
        }); // F:[AUV3-9,15]

        amountOut = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactInput.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV3-9,15]
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        ExactOutputSingleParams memory paramsUpdate = params; // F:[AUV3-5,11]
        paramsUpdate.recipient = creditAccount; // F:[AUV3-5,11]

        amountIn = abi.decode(
            _executeFastCheck(
                creditAccount,
                paramsUpdate.tokenIn,
                paramsUpdate.tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactOutputSingle.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV3-5,11]
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV3-3]

        (address tokenOut, address tokenIn) = _extractTokens(params.path); // F:[AUV3-7,13]

        ExactOutputParams memory paramsUpdate = params; // F:[AUV3-7,13]
        paramsUpdate.recipient = creditAccount; // F:[AUV3-7,13]

        amountIn = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    ISwapRouter.exactOutput.selector,
                    paramsUpdate
                ),
                true
            ),
            (uint256)
        ); // F:[AUV3-7,13]
    }

    function _extractTokens(bytes memory path)
        internal
        pure
        returns (address tokenA, address tokenB)
    {
        if (path.length < MIN_PATH_LENGTH)
            revert IncorrectPathLengthException();
        tokenA = path.toAddress(0);
        tokenB = path.toAddress(
            ((path.length - ADDR_SIZE) / ADDR_PLUS_FEE_LENGTH) *
                ADDR_PLUS_FEE_LENGTH
        );
    }
}
