// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {IBaseRewardPool} from "../../../integrations/convex/IBaseRewardPool.sol";

interface IConvexV1BaseRewardPoolAdapterErrors {
    /// @dev Thrown each time, when reward token is not found in creditManager
    error TokenIsNotAddedToCreditManagerException(address token);
}

interface IConvexV1BaseRewardPoolAdapter is
    IAdapter,
    IBaseRewardPool,
    IConvexV1BaseRewardPoolAdapterErrors
{
    // Errors

    function curveLPtoken() external view returns (address);

    function cvxLPtoken() external view returns (address);

    function stakedPhantomToken() external view returns (address);

    function extraReward1() external view returns (address);

    function extraReward2() external view returns (address);

    function crv() external view returns (address);

    function cvx() external view returns (address);
}
