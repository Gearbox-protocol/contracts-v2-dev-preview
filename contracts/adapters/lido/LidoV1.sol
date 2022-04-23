// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma abicoder v1;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";

// INTERFACES
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IstETH} from "../../integrations/lido/IstETH.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {IPoolService} from "../../interfaces/IPoolService.sol";

import {ILidoV1Adapter} from "../../interfaces/adapters/lido/ILidoV1Adapter.sol";

import {ACLTrait} from "../../core/ACLTrait.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

import {LidoV1Gateway} from "./LidoV1_WETHGateway.sol";

/// @title ConvexV1ClaimZapAdapter adapter
/// @dev Implements logic for claiming all tokens for creditAccount
contract LidoV1Adapter is
    AbstractAdapter,
    ILidoV1Adapter,
    ACLTrait,
    ReentrancyGuard
{
    // Original pool contract
    address public immutable stETH;
    address public immutable weth;
    address public immutable treasury;

    uint256 public limit;

    AdapterType public constant _gearboxAdapterType = AdapterType.LIDO_V1;
    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _stETH Address of staked ETH contract
    constructor(address _creditManager, address _stETH)
        ACLTrait(
            address(
                IPoolService(ICreditManager(_creditManager).poolService())
                    .addressProvider()
            )
        )
        AbstractAdapter(
            _creditManager,
            address(
                new LidoV1Gateway(
                    IPoolService(ICreditManager(_creditManager).poolService())
                        .addressProvider()
                        .getWethToken(),
                    _stETH
                )
            )
        )
    {
        IAddressProvider ap = IPoolService(
            ICreditManager(_creditManager).poolService()
        ).addressProvider();

        stETH = _stETH;
        weth = ap.getWethToken();
        treasury = ap.getTreasuryContract();
        limit = 20 * 10**18; // 20 stETH
    }

    function submit(uint256 amount) external returns (uint256 result) {
        // TODO: cover with test

        if (amount > limit) revert LimitIsOverException();
        limit -= amount;

        result = abi.decode(
            _executeFastCheck(
                weth,
                stETH,
                abi.encodeWithSelector(
                    LidoV1Gateway.submit.selector,
                    amount,
                    treasury
                ),
                true
            ),
            (uint256)
        );
    }

    // TODO: cover with test
    function setLimit(uint256 _limit) external override configuratorOnly {
        limit = _limit;
        emit NewLimit(_limit);
    }
}
