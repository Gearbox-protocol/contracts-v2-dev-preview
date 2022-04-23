// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {CurveV1AdapterBase} from "./CurveV1_Base.sol";
import {ICurveV1Adapter} from "../../interfaces/adapters/curve/ICurveV1Adapter.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {ICurvePool} from "../../integrations/curve/ICurvePool.sol";
import {ICurveMinter} from "../../integrations/curve/ICurveMinter.sol";
import {ICRVToken} from "../../integrations/curve/ICRVToken.sol";
import {ICurveRegistry} from "../../integrations/curve/ICurveRegistry.sol";

import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

// EXCEPTIONS
import {ZeroAddressException, NotImplementedException} from "../../interfaces/IErrors.sol";

import "hardhat/console.sol";

/// @title CurveV1Base adapter
/// @dev Implements exchange logic except liquidity operations
contract CurveV1AdapterMinter is
    AbstractAdapter,
    ICurveMinter,
    ReentrancyGuard
{
    address public immutable crv;

    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _minter Address of the CRV minter contract
    constructor(address _creditManager, address _minter)
        AbstractAdapter(_creditManager, _minter)
    {
        if (_minter == address(0)) revert ZeroAddressException();

        crv = ICurveMinter(_minter).token();
    }

    function mint(address gauge_addr) external {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        creditManager.executeOrder(
            msg.sender,
            address(targetContract),
            msg.data
        );

        creditManager.checkAndEnableToken(creditAccount, crv);
    }

    function token() external view returns (address) {
        return ICurveMinter(targetContract).token();
    }

    function _gearboxAdapterType()
        external
        pure
        virtual
        override
        returns (AdapterType)
    {
        return AdapterType.CURVE_V1_MINTER;
    }

}
