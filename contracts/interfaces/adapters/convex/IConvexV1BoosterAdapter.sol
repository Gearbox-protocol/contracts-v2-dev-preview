// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IAdapter} from "../IAdapter.sol";
import {IBooster} from "../../../integrations/convex/IBooster.sol";


interface IConvexV1BoosterAdapter is IAdapter, IBooster {
    /// @dev returns Booster address
    function booster() external view returns (IBooster);

 }
