// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {ICurveGauge} from "../../../integrations/curve/ICurveGauge.sol";

interface ICurveV1AdapterGaugeErrors {
    /// @dev Thrown each time, when reward token is not found in creditManager
    error TokenIsNotAddedToCreditManagerException(address token);
}

interface ICurveV1AdapterGauge is
    IAdapter,
    ICurveGauge,
    ICurveV1AdapterGaugeErrors
{
    function curveLPtoken() external view returns (address);

    function gauge() external view returns (address);

    function extraReward1() external view returns (address);

    function extraReward2() external view returns (address);
}
