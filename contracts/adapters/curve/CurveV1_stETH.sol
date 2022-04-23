// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {CurveV1AdapterBase} from "./CurveV1_Base.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {ICurveV1Adapter} from "../../interfaces/adapters/curve/ICurveV1Adapter.sol";

import {N_COINS, ICurvePool2Assets} from "../../integrations/curve/ICurvePool_2.sol";
import {ICurvePool} from "../../integrations/curve/ICurvePool.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

import {CurveV1Adapter2Assets} from "./CurveV1_2.sol";

/// @title CurveV1AdapterStETH adapter
/// @dev Designed to work with CurveV1StETH Wrapper. The difference here, that this adapter should appove lp token to wrapper to
/// make transferFrom available
contract CurveV1AdapterStETH is CurveV1Adapter2Assets {
    constructor(address _creditManager, address _curvePool)
        CurveV1Adapter2Assets(_creditManager, _curvePool)
    {}

    function remove_liquidity(
        uint256 amount,
        uint256[N_COINS] memory min_amounts
    ) public override nonReentrant {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        creditManager.approveCreditAccount(
            msg.sender,
            targetContract,
            address(token),
            type(uint256).max
        ); // F:[ACV1_2-4]

        _enable_tokens(creditAccount, min_amounts);
        _executeFullCheck(creditAccount, msg.data); //F:[ACV1_2-5,6]
    }

    function remove_liquidity_one_coin(
        uint256, // _token_amount,
        int128 i,
        uint256 // min_amount
    ) external override nonReentrant {
        creditManager.approveCreditAccount(
            msg.sender,
            targetContract,
            address(lp_token),
            type(uint256).max
        ); // F:[ACV1_2-4]
        address tokenOut = _get_token(i);
        _remove_liquidity_one_coin(tokenOut, msg.data);
    }

    function remove_all_liquidity_one_coin(int128 i, uint256 minRateRAY)
        external
        override
        nonReentrant
    {
        creditManager.approveCreditAccount(
            msg.sender,
            targetContract,
            address(lp_token),
            type(uint256).max
        ); // F:[ACV1_2-4]
        address tokenOut = _get_token(i);
        _remove_all_liquidity_one_coin(i, tokenOut, minRateRAY);
    }

    function remove_liquidity_imbalance(
        uint256[N_COINS] memory amounts,
        uint256 max_burn_amount
    ) external override nonReentrant {
        creditManager.approveCreditAccount(
            msg.sender,
            targetContract,
            address(lp_token),
            type(uint256).max
        ); // F:[ACV1_2-4]

        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[ACV1_2-3]

        _enable_tokens(creditAccount, amounts);
        _executeFullCheck(creditAccount, msg.data); //F:[ACV1_2-5,6]
    }
}
