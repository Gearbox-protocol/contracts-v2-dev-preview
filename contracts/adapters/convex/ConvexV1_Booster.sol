// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {IBooster} from "../../integrations/convex/IBooster.sol";
import {IConvexV1BaseRewardPoolAdapter} from "../../interfaces/adapters/convex/IConvexV1BaseRewardPoolAdapter.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";

import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";

import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {IPoolService} from "../../interfaces/IPoolService.sol";

import {ACLTrait} from "../../core/ACLTrait.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {ICreditConfigurator} from "../../interfaces/ICreditConfigurator.sol";
import {ICreditFacade} from "../../interfaces/ICreditFacade.sol";

import {RAY} from "../../libraries/WadRayMath.sol";


import "hardhat/console.sol";

/// @title ConvexV1BoosterAdapter adapter
/// @dev Implements convex logic
contract ConvexV1BoosterAdapter is
    AbstractAdapter,
    IBooster,
    ACLTrait,
    ReentrancyGuard
{
    address public immutable crv;
    address public immutable minter;

    /// @dev Maps pid to a pseudo-ERC20 token that represents the staked position
    mapping(uint256 => address) public pidToPhantomToken;

    AdapterType public constant _gearboxAdapterType =
        AdapterType.CONVEX_V1_BOOSTER;
    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _booster Address of Booster contract
    constructor(address _creditManager, address _booster)
        ACLTrait(
            address(
                IPoolService(ICreditManager(_creditManager).poolService())
                    .addressProvider()
            )
        )
        AbstractAdapter(_creditManager, _booster)
    {
        crv = IBooster(_booster).crv(); // F: [ACVX1_B_01]
        minter = IBooster(_booster).minter(); // F: [ACVX1_B_01]
        _updateStakedPhantomTokensMap(); // F: [ACVX1_B_01]
    }

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool) {
        return _deposit(_pid, _stake, msg.data);
    }

    function depositAll(uint256 _pid, bool _stake) external returns (bool) {
        return _deposit(_pid, _stake, msg.data);
    }

    function _deposit(
        uint256 _pid,
        bool _stake,
        bytes memory callData
    ) internal returns (bool) {
        PoolInfo memory pool = IBooster(targetContract).poolInfo(_pid);

        address tokenIn = pool.lptoken; // F: [ACVX1_B_02-05]
        address tokenOut = _stake ? pidToPhantomToken[_pid] : pool.token; // F: [ACVX1_B_02-05]

        _executeFastCheck(tokenIn, tokenOut, callData, true);

        return true;
    }

    // Consider making an internal _withdraw function to make the contract shorter

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool) {
        return _withdraw(_pid, msg.data);
    }

    function withdrawAll(uint256 _pid) external returns (bool) {
        return _withdraw(_pid, msg.data);
    }

    function _withdraw(uint256 _pid, bytes memory callData)
        internal
        returns (bool)
    {
        PoolInfo memory pool = IBooster(targetContract).poolInfo(_pid);

        address tokenIn = pool.token; // F: [ACVX1_B_06-07]
        address tokenOut = pool.lptoken; // F: [ACVX1_B_06-07]

        _executeFastCheck(tokenIn, tokenOut, callData, false);

        return true;
    }

    //
    // GETTERS
    //

    function poolInfo(uint256 i) external view returns (PoolInfo memory) {
        return IBooster(targetContract).poolInfo(i); // F: [ACVX1_B_08]
    }

    function poolLength() external view returns (uint256) {
        return IBooster(targetContract).poolLength(); // F: [ACVX1_B_08]
    }

    function staker() external view returns (address) {
        return IBooster(targetContract).staker(); // F: [ACVX1_B_08]
    }

    ///
    /// CONFIGURATION
    ///

    function updateStakedPhantomTokensMap() external configuratorOnly {
        _updateStakedPhantomTokensMap(); // F: [ACVX1_B_09]
    }

    function _updateStakedPhantomTokensMap() internal {
        ICreditConfigurator cc = ICreditConfigurator(
            creditManager.creditConfigurator()
        );
        ICreditFacade cf = ICreditFacade(creditManager.creditFacade());
        uint256 len = cc.allowedContractsCount();

        for (uint256 i = 0; i < len; ) {
            address allowedContract = cc.allowedContracts(i);
            address adapter = cf.contractToAdapter(allowedContract);
            AdapterType aType = IAdapter(adapter)._gearboxAdapterType();

            if (aType == AdapterType.CONVEX_V1_BASE_REWARD_POOL) {
                uint256 pid = IConvexV1BaseRewardPoolAdapter(adapter).pid();
                pidToPhantomToken[pid] = IConvexV1BaseRewardPoolAdapter(adapter)
                .stakedPhantomToken();
            }

            unchecked {
                ++i;
            }
        }
    }
}
