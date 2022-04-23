// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma abicoder v1;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AbstractAdapter} from "../AbstractAdapter.sol";

import {IClaimZap} from "../../integrations/convex/IClaimZap.sol";
import {IRewards} from "../../integrations/convex/IRewards.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {IPoolService} from "../../interfaces/IPoolService.sol";

import {ACLTrait} from "../../core/ACLTrait.sol";
import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";
import {RAY} from "../../libraries/WadRayMath.sol";

import "hardhat/console.sol";

/// @title ConvexV1ClaimZapAdapter adapter
/// @dev Implements logic for claiming all tokens for creditAccount
contract ConvexV1ClaimZapAdapter is
    AbstractAdapter,
    IClaimZap,
    ReentrancyGuard
{
    AdapterType public constant _gearboxAdapterType =
        AdapterType.CONVEX_V1_CLAIM_ZAP;
    uint16 public constant _gearboxAdapterVersion = 1;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _claimZap Address of Booster contract
    constructor(address _creditManager, address _claimZap)
        AbstractAdapter(_creditManager, _claimZap)
    {}

    function claimRewards(
        address[] calldata rewardContracts,
        address[] calldata extraRewardContracts,
        address[] calldata tokenRewardContracts,
        address[] calldata tokenRewardTokens,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {

      // ClaimZap adapter currently does not support additional options

      bytes memory data = abi.encodePacked(
        msg.data[:4 + 4 * 32],
        uint256(0),
        uint256(0),
        uint256(0),
        uint256(0),
        uint256(0),
        msg.data[4 + 9 * 32:]
      );

      creditManager.executeOrder(msg.sender, targetContract, data);

      _enableRewardTokens(
          rewardContracts,
          extraRewardContracts,
          tokenRewardTokens
        );

    }

    function _enableRewardTokens(
      address[] memory rewardContracts,
      address[] memory extraRewardContracts,
      address[] memory tokenRewardTokens
    ) internal {

      address creditAccount = creditManager.getCreditAccountOrRevert(
          msg.sender
      );

      address token;

      for (uint i = 0; i < rewardContracts.length; ) {

        token = IRewards(rewardContracts[i]).rewardToken();

        if (IERC20(token).balanceOf(creditAccount) > 1) {
          creditManager.checkAndEnableToken(
            creditAccount,
            token
          );
        }

        unchecked {
          ++i;
        }
      }

      for (uint i = 0; i < extraRewardContracts.length; ) {

        token = IRewards(extraRewardContracts[i]).rewardToken();

        if (IERC20(token).balanceOf(creditAccount) > 1) {
          creditManager.checkAndEnableToken(
            creditAccount,
            token
          );
        }

        unchecked {
          ++i;
        }
      }

      for (uint i = 0; i < tokenRewardTokens.length; ) {

        if (IERC20(tokenRewardTokens[i]).balanceOf(creditAccount) > 1) {
          creditManager.checkAndEnableToken(
            creditAccount,
            tokenRewardTokens[i]
          );
        }

        unchecked {
          ++i;
        }
      }
    }
}
