// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {IBooster} from "../../../integrations/convex/IBooster.sol";

interface ILidoV1AdapterEvents {
    event NewLimit(uint256 _limit);
}

interface ILidoV1AdapterExceptions {
    error LimitIsOverException();
}

interface ILidoV1Adapter is
    IAdapter,
    ILidoV1AdapterEvents,
    ILidoV1AdapterExceptions
{
    function setLimit(uint256 _limit) external;
}
