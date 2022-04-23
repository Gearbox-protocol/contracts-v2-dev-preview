// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

// LIBRARIES
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {CurveV1AdapterBase} from "./CurveV1_Base.sol";

// INTERFACES
import {ICurveV1Adapter} from "../../interfaces/adapters/curve/ICurveV1Adapter.sol";
import {N_COINS, ICurvePool2Assets} from "../../integrations/curve/ICurvePool_2.sol";
import {ICurvePool} from "../../integrations/curve/ICurvePool.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";

// CONSTANTS
import {RAY} from "../../libraries/WadRayMath.sol";

// EXCEPTIONS
import {ZeroAddressException} from "../../interfaces/IErrors.sol";

/// @title CurveV1 adapter
contract CurveV1Adapter2Assets is CurveV1AdapterBase, ICurvePool2Assets {
    address public immutable token0;
    address public immutable token1;

    AdapterType public constant override _gearboxAdapterType =
        AdapterType.CURVE_V1_2ASSETS;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _curvePool Address of curve-compatible pool
    constructor(address _creditManager, address _curvePool)
        CurveV1AdapterBase(_creditManager, _curvePool)
    {
        token0 = ICurvePool2Assets(_curvePool).coins(0); // F:[ACV1_2-1]
        token1 = ICurvePool2Assets(_curvePool).coins(1); // F:[ACV1_2-1]

        if (token0 == address(0) || token1 == address(0))
            revert ZeroAddressException(); // F:[ACV1_2-2]
    }

    function add_liquidity(uint256[N_COINS] memory amounts, uint256)
        external
        nonReentrant
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        if (amounts[0] > 0) {
            creditManager.approveCreditAccount(
                msg.sender,
                targetContract,
                token0,
                type(uint256).max
            ); // F:[ACV1_2-4]
        }

        if (amounts[1] > 0) {
            creditManager.approveCreditAccount(
                msg.sender,
                targetContract,
                token1,
                type(uint256).max
            ); // F:[ACV1_2-4]
        }

        creditManager.checkAndEnableToken(creditAccount, address(lp_token)); // F:[ACV1_2-4]
        _executeFullCheck(creditAccount, msg.data); // F:[ACV1_2-4]
    }

    function add_all_liquidity_one_coin(int128 i, uint256 rateMinRAY)
        external
        override
        nonReentrant
    {
        address tokenIn = _get_token(i);

        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        uint256 amount = IERC20(tokenIn).balanceOf(creditAccount) - 1; //F:[ACV1-5,7]
        uint256[N_COINS] memory amounts;
        amounts[uint256(uint128(i))] = amount;

        _executeFastCheck(
            creditAccount,
            tokenIn,
            lp_token,
            abi.encodeWithSelector(
                ICurvePool2Assets.add_liquidity.selector,
                amounts,
                (amount * rateMinRAY) / RAY
            ),
            false
        );
    }

    function remove_liquidity(uint256, uint256[N_COINS] memory min_amounts)
        external
        virtual
        nonReentrant
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        _enable_tokens(creditAccount, min_amounts);
        _executeFullCheck(creditAccount, msg.data); //F:[ACV1_2-5,6]
    }

    function remove_liquidity_one_coin(
        uint256, // _token_amount,
        int128 i,
        uint256 // min_amount
    ) external virtual override(CurveV1AdapterBase, ICurvePool) nonReentrant {
        address tokenOut = _get_token(i);
        _remove_liquidity_one_coin(tokenOut, msg.data);
    }

    function remove_all_liquidity_one_coin(int128 i, uint256 minRateRAY)
        external
        virtual
        override
        nonReentrant
    {
        address tokenOut = _get_token(i);
        _remove_all_liquidity_one_coin(i, tokenOut, minRateRAY);
    }

    function remove_liquidity_imbalance(
        uint256[N_COINS] memory amounts,
        uint256
    ) external virtual override nonReentrant {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        _enable_tokens(creditAccount, amounts);
        _executeFullCheck(creditAccount, msg.data); //F:[ACV1_2-5,6]
    }

    //
    // INTERNAL
    //

    function _get_token(int128 i) internal view returns (address) {
        require(i <= int128(uint128(N_COINS)), "Incorrect index");
        return (i == 0) ? token0 : token1;
    }

    function _enable_tokens(
        address creditAccount,
        uint256[N_COINS] memory amounts
    ) internal {
        if (amounts[0] > 1) {
            creditManager.checkAndEnableToken(creditAccount, token0); //F:[ACV1_2-5,6]
        }

        if (amounts[1] > 1) {
            creditManager.checkAndEnableToken(creditAccount, token1); //F:[ACV1_2-5,6]
        }
    }
}
