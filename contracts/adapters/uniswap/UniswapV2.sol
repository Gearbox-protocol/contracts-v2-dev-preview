// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {IUniswapV2Router02} from "../../integrations/uniswap/IUniswapV2Router02.sol";
import {IUniswapV2Adapter} from "../../interfaces/adapters/uniswap/IUniswapV2Adapter.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";

import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

// EXCEPTIONS
import {NotImplementedException} from "../../interfaces/IErrors.sol";

/// @title UniswapV2 Router adapter
contract UniswapV2Adapter is
    AbstractAdapter,
    IUniswapV2Adapter,
    ReentrancyGuard
{
    AdapterType public constant _gearboxAdapterType = AdapterType.UNISWAP_V2;
    uint16 public constant _gearboxAdapterVersion = 2;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _router Address of IUniswapV2Router02
    constructor(address _creditManager, address _router)
        AbstractAdapter(_creditManager, _router)
    {}

    /**
     * @dev Swap tokens to exact tokens using Uniswap-compatible protocol
     * - checks that swap contract is allowed
     * - checks that in/out tokens are in allowed list
     * - checks that required allowance is enough, if not - set it to MAX_INT
     * - call swap function on credit account contracts
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param path An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of
     *        addresses must exist and have liquidity.
     * @param deadline Unix timestamp after which the transaction will revert.
     * for more information check uniswap documentation: https://uniswap.org/docs/v2/smart-contracts/router02/
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address,
        uint256 deadline
    ) external override nonReentrant returns (uint256[] memory amounts) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV2-3]

        address tokenIn = path[0]; // F:[AUV2-5,9,10]
        address tokenOut = path[path.length - 1]; // F:[AUV2-5,9,10]

        amounts = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    IUniswapV2Router02.swapTokensForExactTokens.selector,
                    amountOut,
                    amountInMax,
                    path,
                    creditAccount,
                    deadline
                ),
                true
            ),
            (uint256[])
        ); // F:[AUV2-5,9,10]
    }

    /**
     * Swaps exact tokens to tokens on Uniswap compatible protocols
     * - checks that swap contract is allowed
     * - checks that in/out tokens are in allowed list
     * - checks that required allowance is enough, if not - set it to MAX_INT
     * - call swap function on credit account contracts
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path An array of token addresses. path.length must be >= 2. Pools for each consecutive pair of
     *        addresses must exist and have liquidity.
     * deadline Unix timestamp after which the transaction will revert.
     * for more information check uniswap documentation: https://uniswap.org/docs/v2/smart-contracts/router02/
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address,
        uint256 deadline
    ) external override nonReentrant returns (uint256[] memory amounts) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV2-3]

        address tokenIn = path[0]; // F:[AUV2-4,7,8]
        address tokenOut = path[path.length - 1]; // F:[AUV2-4,7,8]

        amounts = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    IUniswapV2Router02.swapExactTokensForTokens.selector,
                    amountIn,
                    amountOutMin,
                    path,
                    creditAccount,
                    deadline
                ),
                true
            ),
            (uint256[])
        ); // F:[AUV2-5,9,10]
    }

    function swapAllTokensForTokens(
        uint256 rateMinRAY,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant returns (uint256[] memory amounts) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AUV2-3]

        address tokenIn = path[0]; // F:[AUV2-6]
        address tokenOut = path[path.length - 1]; // F:[AUV2-6]

        uint256 balanceInBefore = IERC20(tokenIn).balanceOf(creditAccount); // F:[AUV2-6]

        amounts = abi.decode(
            _executeFastCheck(
                creditAccount,
                tokenIn,
                tokenOut,
                abi.encodeWithSelector(
                    IUniswapV2Router02.swapExactTokensForTokens.selector,
                    balanceInBefore - 1,
                    ((balanceInBefore - 1) * rateMinRAY) / RAY,
                    path,
                    creditAccount,
                    deadline
                ),
                true
            ),
            (uint256[])
        ); // F:[AUV2-5,9,10]
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address, // token,
        uint256, // liquidity,
        uint256, // amountTokenMin,
        uint256, // amountETHMin,
        address, // to,
        uint256 // deadline
    ) external pure override returns (uint256) {
        revert NotImplementedException();
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address, // token,
        uint256, // liquidity,
        uint256, // amountTokenMin,
        uint256, // amountETHMin,
        address, // to,
        uint256, // deadline,
        bool, // approveMax,
        uint8, // v,
        bytes32, // r,
        bytes32 // s
    ) external pure override returns (uint256) {
        revert NotImplementedException();
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256, // amountIn,
        uint256, // amountOutMin,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external pure override {
        revert NotImplementedException();
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256, // amountOutMin,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external payable override {
        revert NotImplementedException();
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256, // amountIn,
        uint256, // amountOutMin,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external pure override {
        revert NotImplementedException();
    }

    function factory() external view override returns (address) {
        return IUniswapV2Router02(targetContract).factory();
    }

    function WETH() external view override returns (address) {
        return IUniswapV2Router02(targetContract).WETH();
    }

    function addLiquidity(
        address, // tokenA,
        address, // tokenB,
        uint256, // amountADesired,
        uint256, // amountBDesired,
        uint256, // amountAMin,
        uint256, // amountBMin,
        address, // to,
        uint256 // deadline
    )
        external
        pure
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        revert NotImplementedException();
    }

    function addLiquidityETH(
        address, // token,
        uint256, // amountTokenDesired,
        uint256, // amountTokenMin,
        uint256, // amountETHMin,
        address, // to,
        uint256 // deadline
    )
        external
        payable
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        revert NotImplementedException();
    }

    function removeLiquidity(
        address, // tokenA,
        address, // tokenB,
        uint256, // liquidity,
        uint256, // amountAMin,
        uint256, // amountBMin,
        address, // to,
        uint256 // deadline
    ) external pure override returns (uint256, uint256) {
        revert NotImplementedException();
    }

    function removeLiquidityETH(
        address, // token,
        uint256, // liquidity,
        uint256, // amountTokenMin,
        uint256, // amountETHMin,
        address, // to,
        uint256 // deadline
    ) external pure override returns (uint256, uint256) {
        revert NotImplementedException();
    }

    function removeLiquidityWithPermit(
        address, // tokenA,
        address, // tokenB,
        uint256, // liquidity,
        uint256, // amountAMin,
        uint256, // amountBMin,
        address, // to,
        uint256, // deadline,
        bool, // approveMax,
        uint8, // v,
        bytes32, // r,
        bytes32 // s
    ) external pure override returns (uint256, uint256) {
        revert NotImplementedException();
    }

    function removeLiquidityETHWithPermit(
        address, // token,
        uint256, // liquidity,
        uint256, // amountTokenMin,
        uint256, // amountETHMin,
        address, // to,
        uint256, // deadline,
        bool, // approveMax,
        uint8, // v,
        bytes32, // r,
        bytes32 // s
    ) external pure override returns (uint256, uint256) {
        revert NotImplementedException();
    }

    function swapExactETHForTokens(
        uint256, // amountOutMin,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external payable override returns (uint256[] memory) {
        revert NotImplementedException();
    }

    function swapTokensForExactETH(
        uint256, // amountOut,
        uint256, // amountInMax,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external pure override returns (uint256[] memory) {
        revert NotImplementedException();
    }

    function swapExactTokensForETH(
        uint256, // amountIn,
        uint256, //amountOutMin,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external pure override returns (uint256[] memory) {
        revert NotImplementedException();
    }

    function swapETHForExactTokens(
        uint256, // amountOut,
        address[] calldata, // path,
        address, // to,
        uint256 // deadline
    ) external payable override returns (uint256[] memory) {
        revert NotImplementedException();
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external view override returns (uint256 amountB) {
        return
            IUniswapV2Router02(targetContract).quote(
                amountA,
                reserveA,
                reserveB
            );
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view override returns (uint256 amountOut) {
        return
            IUniswapV2Router02(targetContract).getAmountOut(
                amountIn,
                reserveIn,
                reserveOut
            );
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view override returns (uint256 amountIn) {
        return
            IUniswapV2Router02(targetContract).getAmountIn(
                amountOut,
                reserveIn,
                reserveOut
            );
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return IUniswapV2Router02(targetContract).getAmountsOut(amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        return IUniswapV2Router02(targetContract).getAmountsIn(amountOut, path);
    }
}
