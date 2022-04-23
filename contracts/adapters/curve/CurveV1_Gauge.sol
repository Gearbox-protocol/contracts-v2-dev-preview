// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";

import {ICurveGauge} from "../../integrations/curve/ICurveGauge.sol";
import {IRewards} from "../../integrations/convex/Interfaces.sol";
import {AdapterType} from "../../interfaces/adapters/IAdapter.sol";

import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {ICreditConfigurator} from "../../interfaces/ICreditConfigurator.sol";
import {ICreditFacade} from "../../interfaces/ICreditFacade.sol";
import {ICurveV1AdapterGauge} from "../../interfaces/adapters/curve/ICurveV1AdapterGauge.sol";

import {IPoolService} from "../../interfaces/IPoolService.sol";

import {ACLTrait} from "../../core/ACLTrait.sol";
import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

// EXCEPTIONS
import {NotImplementedException} from "../../interfaces/IErrors.sol";

import "hardhat/console.sol";

/// @title CurveV1AdapterGauge adapter
/// @dev Implements logic for a Curve gauge
contract CurveV1AdapterGauge is
    AbstractAdapter,
    ICurveGauge,
    ICurveV1AdapterGauge,
    ReentrancyGuard
{
    address public immutable curveLPtoken;
    address public immutable gauge;
    address public immutable extraReward1;
    address public immutable extraReward2;

    AdapterType public constant _gearboxAdapterType =
        AdapterType.CURVE_V1_GAUGE;
    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _gauge Address of the gauge
    constructor(address _creditManager, address _gauge)
        AbstractAdapter(_creditManager, _gauge)
    {
        gauge = _gauge;
        curveLPtoken = ICurveGauge(_gauge).lp_token();

        address _extraReward1;
        address _extraReward2;

        try ICurveGauge(_gauge).reward_tokens(0) {
            _extraReward1 = ICurveGauge(_gauge).reward_tokens(0);
            _extraReward2 = ICurveGauge(_gauge).reward_tokens(1);
        } catch {}

        extraReward1 = _extraReward1;
        extraReward2 = _extraReward2;

        if (creditManager.tokenMasksMap(gauge) == 0)
            revert TokenIsNotAddedToCreditManagerException(gauge);

        if (creditManager.tokenMasksMap(curveLPtoken) == 0)
            revert TokenIsNotAddedToCreditManagerException(curveLPtoken);

        if (
            _extraReward1 != address(0) &&
            creditManager.tokenMasksMap(_extraReward1) == 0
        ) revert TokenIsNotAddedToCreditManagerException(_extraReward1);

        if (
            _extraReward2 != address(0) &&
            creditManager.tokenMasksMap(_extraReward2) == 0
        ) revert TokenIsNotAddedToCreditManagerException(_extraReward2);
    }

    function deposit(uint256 _value) external {
        _executeFastCheck(curveLPtoken, gauge, msg.data, true);
    }

    function withdraw(uint256 _value) external {
        _executeFastCheck(gauge, curveLPtoken, msg.data, true);
    }

    function claim_rewards() external {
        if (extraReward1 == address(0)) {
            revert(); // TODO: Add proper exception
        }

        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        creditManager.executeOrder(
            msg.sender,
            address(targetContract),
            msg.data
        );

        _enableExtraRewards(creditAccount);

    }

    function claim_historic_rewards(address[8] calldata _reward_tokens) external {
        revert NotImplementedException();
    }

    function kick(address addr) external {
        revert NotImplementedException();
    }

    function set_approve_deposit(address addr, bool can_deposit) external {
        revert NotImplementedException();
    }

    function user_checkpoint(address addr) external returns (bool) {
        revert NotImplementedException();
    }

    function minter() public view returns (address) {
        return ICurveGauge(targetContract).minter();
    }

    function crv_token() public view returns (address) {
        return ICurveGauge(targetContract).crv_token();
    }

    function lp_token() public view returns (address) {
        return ICurveGauge(targetContract).lp_token();
    }

    function controller() public view returns (address) {
        return ICurveGauge(targetContract).controller();
    }

    function voting_escrow() public view returns (address) {
        return ICurveGauge(targetContract).voting_escrow();
    }

    function future_epoch_time() public view returns (uint256) {
        return ICurveGauge(targetContract).future_epoch_time();
    }

    function reward_tokens(uint256 i) public view returns (address) {
        return ICurveGauge(targetContract).reward_tokens(i);
    }

    function claimable_tokens(address addr) external view returns (uint256) {
        return ICurveGauge(targetContract).claimable_tokens(addr);
    }
    function claimable_reward(address addr) external view returns (uint256) {
        return ICurveGauge(targetContract).claimable_reward(addr);
    }

    function _enableExtraRewards(address creditAccount) internal {

        creditManager.checkAndEnableToken(creditAccount, extraReward1);
        if (extraReward2 != address(0)) {
            creditManager.checkAndEnableToken(creditAccount, extraReward2);
        }

    }

}
