// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {ConvexStakedPositionToken} from "./ConvexV1_StakedPositionToken.sol";

import {IBooster} from "../../integrations/convex/IBooster.sol";
import {IBaseRewardPool} from "../../integrations/convex/IBaseRewardPool.sol";
import {IRewards} from "../../integrations/convex/Interfaces.sol";
import {AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {IConvexV1BaseRewardPoolAdapter} from "../../interfaces/adapters/convex/IConvexV1BaseRewardPoolAdapter.sol";

import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {ICreditConfigurator} from "../../interfaces/ICreditConfigurator.sol";
import {ICreditFacade} from "../../interfaces/ICreditFacade.sol";

import {IPoolService} from "../../interfaces/IPoolService.sol";
import {IPhantomERC20} from "../../interfaces/IPhantomERC20.sol";

import {ACLTrait} from "../../core/ACLTrait.sol";
import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

// EXCEPTIONS
import {NotImplementedException} from "../../interfaces/IErrors.sol";

import "hardhat/console.sol";

/// @title ConvexV1BaseRewardPoolAdapter adapter
/// @dev Implements logic for convex BaseRewardPool
contract ConvexV1BaseRewardPoolAdapter is
    AbstractAdapter,
    IBaseRewardPool,
    IConvexV1BaseRewardPoolAdapter,
    ReentrancyGuard
{
    address public immutable override curveLPtoken;
    address public immutable override cvxLPtoken;
    address public immutable override stakedPhantomToken;
    address public immutable override extraReward1;
    address public immutable override extraReward2;

    address public immutable override crv;
    address public immutable override cvx;

    AdapterType public constant _gearboxAdapterType =
        AdapterType.CONVEX_V1_BASE_REWARD_POOL;
    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _baseRewardPool Address of Booster contract
    constructor(address _creditManager, address _baseRewardPool)
        AbstractAdapter(_creditManager, _baseRewardPool)
    {
        cvxLPtoken = address(IBaseRewardPool(_baseRewardPool).stakingToken()); // F: [ACVX1_P_01]

        stakedPhantomToken = address(
            new ConvexStakedPositionToken(
                _baseRewardPool,
                cvxLPtoken
            )
        );

        address _extraReward1;
        address _extraReward2;

        uint256 extraRewardLength = IBaseRewardPool(_baseRewardPool)
            .extraRewardsLength();

        if (extraRewardLength >= 1) {
            _extraReward1 = IRewards(
                IBaseRewardPool(_baseRewardPool).extraRewards(0)
            ).rewardToken();

            if (extraRewardLength >= 2) {
                _extraReward2 = IRewards(
                    IBaseRewardPool(_baseRewardPool).extraRewards(1)
                ).rewardToken();
            }
        }

        extraReward1 = _extraReward1; // F: [ACVX1_P_01]
        extraReward2 = _extraReward2; // F: [ACVX1_P_01]

        address booster = IBaseRewardPool(_baseRewardPool).operator();

        crv = IBooster(booster).crv(); // F: [ACVX1_P_01]
        cvx = IBooster(booster).minter(); // F: [ACVX1_P_01]

        IBooster.PoolInfo memory poolInfo = IBooster(booster).poolInfo(
            IBaseRewardPool(_baseRewardPool).pid()
        );

        curveLPtoken = poolInfo.lptoken; // F: [ACVX1_P_01]

        if (creditManager.tokenMasksMap(crv) == 0)
            revert TokenIsNotAddedToCreditManagerException(crv); // F: [ACVX1_P_02]

        if (creditManager.tokenMasksMap(cvx) == 0)
            revert TokenIsNotAddedToCreditManagerException(cvx); // F: [ACVX1_P_02]

        if (creditManager.tokenMasksMap(curveLPtoken) == 0)
            revert TokenIsNotAddedToCreditManagerException(curveLPtoken); // F: [ACVX1_P_02]

        if (
            _extraReward1 != address(0) &&
            creditManager.tokenMasksMap(_extraReward1) == 0
        ) revert TokenIsNotAddedToCreditManagerException(_extraReward1); // F: [ACVX1_P_02]

        if (
            _extraReward2 != address(0) &&
            creditManager.tokenMasksMap(_extraReward2) == 0
        ) revert TokenIsNotAddedToCreditManagerException(_extraReward2); // F: [ACVX1_P_02]
    }

    function stake(uint256) external override returns (bool) {
        _executeFastCheck(cvxLPtoken, stakedPhantomToken, msg.data, true); // F: [ACVX1_P_03]
        return true;
    }

    function stakeAll() external override returns (bool) {
        _executeFastCheck(cvxLPtoken, stakedPhantomToken, msg.data, true); // F: [ACVX1_P_04]
        return true;
    }

    function stakeFor(address, uint256) external pure override returns (bool) {
        revert NotImplementedException(); // F: [ACVX1_P_05]
    }

    function withdraw(uint256, bool claim) external override returns (bool) {
        return _withdraw(msg.data, claim); // F: [ACVX1_P_09]
    }

    function withdrawAll(bool claim) external override {
        _withdraw(msg.data, claim); // F: [ACVX1_P_10]
    }

    function _withdraw(bytes memory callData, bool claim)
        internal
        returns (bool)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        _executeFastCheck(
            creditAccount,
            stakedPhantomToken,
            cvxLPtoken,
            callData,
            false
        );

        if (claim) {
            _enableRewardTokens(creditAccount, true);
        }

        return true;
    }

    function withdrawAndUnwrap(uint256, bool claim)
        external
        override
        returns (bool)
    {
        _withdrawAndUnwrap(msg.data, claim); // F: [ACVX1_P_11]
        return true;
    }

    function withdrawAllAndUnwrap(bool claim) external override {
        _withdrawAndUnwrap(msg.data, claim); // F: [ACVX1_P_12]
    }

    function _withdrawAndUnwrap(bytes memory callData, bool claim) internal {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        _executeFastCheck(
            creditAccount,
            stakedPhantomToken,
            curveLPtoken,
            callData,
            false
        );

        if (claim) {
            _enableRewardTokens(creditAccount, true);
        }
    }

    function getReward(address _account, bool _claimExtras)
        external
        override
        returns (bool)
    {

        IBaseRewardPool(targetContract).getReward(_account, _claimExtras); // F: [ACVX1_P_06-07]
        _enableRewardTokens(_account, _claimExtras);

        return true;
    }

    function getReward() external override returns (bool) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        creditManager.executeOrder(
            msg.sender,
            address(targetContract),
            msg.data
        ); // F: [ACVX1_P_08]

        _enableRewardTokens(creditAccount, true);

        return true;
    }

    function donate(uint256 _amount) external override returns (bool) {
        // TODO: make implementation
        // IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        // queuedRewards = queuedRewards.add(_amount);
    }

    // TODO: Only enable tokens when balance > 1 (to account for some possibly not being claimed)
    function _enableRewardTokens(address creditAccount, bool claimExtras) internal {  // F: [ACVX1_P_03-12]
        creditManager.checkAndEnableToken(creditAccount, crv);
        creditManager.checkAndEnableToken(creditAccount, cvx);

        if ((extraReward1 != address(0)) && claimExtras) { // F: [ACVX1_P_06-07]
            creditManager.checkAndEnableToken(creditAccount, extraReward1);

            if (extraReward2 != address(0)) {
                creditManager.checkAndEnableToken(creditAccount, extraReward2);
            }
        }
    }

    //
    // GETTERS
    //

    function earned(address account) public view override returns (uint256) {
        return IBaseRewardPool(targetContract).earned(account); // F: [ACVX1_P_13]
    }

    function lastTimeRewardApplicable()
        external
        view
        override
        returns (uint256)
    {
        return IBaseRewardPool(targetContract).lastTimeRewardApplicable(); // F: [ACVX1_P_13]
    }

    function rewardPerToken() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).rewardPerToken(); // F: [ACVX1_P_13]
    }

    function totalSupply() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).totalSupply(); // F: [ACVX1_P_13]
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return IBaseRewardPool(targetContract).balanceOf(account); // F: [ACVX1_P_13]
    }

    function extraRewardsLength() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).extraRewardsLength(); // F: [ACVX1_P_13]
    }

    function rewardToken() external view override returns (IERC20) {
        return IBaseRewardPool(targetContract).rewardToken(); // F: [ACVX1_P_13]
    }

    function stakingToken() external view override returns (IERC20) {
        return IBaseRewardPool(targetContract).stakingToken(); // F: [ACVX1_P_13]
    }

    function duration() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).duration(); // F: [ACVX1_P_13]
    }

    function operator() external view override returns (address) {
        return IBaseRewardPool(targetContract).operator(); // F: [ACVX1_P_13]
    }

    function rewardManager() external view override returns (address) {
        return IBaseRewardPool(targetContract).rewardManager(); // F: [ACVX1_P_13]
    }

    function pid() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).pid(); // F: [ACVX1_P_13]
    }

    function periodFinish() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).periodFinish(); // F: [ACVX1_P_13]
    }

    function rewardRate() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).rewardRate(); // F: [ACVX1_P_13]
    }

    function lastUpdateTime() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).lastUpdateTime(); // F: [ACVX1_P_13]
    }

    function rewardPerTokenStored() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).rewardPerTokenStored(); // F: [ACVX1_P_13]
    }

    function queuedRewards() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).queuedRewards(); // F: [ACVX1_P_13]
    }

    function currentRewards() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).currentRewards(); // F: [ACVX1_P_13]
    }

    function historicalRewards() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).historicalRewards(); // F: [ACVX1_P_13]
    }

    function newRewardRatio() external view override returns (uint256) {
        return IBaseRewardPool(targetContract).newRewardRatio(); // F: [ACVX1_P_13]
    }

    function userRewardPerTokenPaid(address account)
        external
        view
        override
        returns (uint256)
    {
        return IBaseRewardPool(targetContract).userRewardPerTokenPaid(account); // F: [ACVX1_P_13]
    }

    function rewards(address account) external view override returns (uint256) {
        return IBaseRewardPool(targetContract).rewards(account); // F: [ACVX1_P_13]
    }

    function extraRewards(uint256 i) external view override returns (address) {
        return IBaseRewardPool(targetContract).extraRewards(i); // F: [ACVX1_P_13]
    }
}
