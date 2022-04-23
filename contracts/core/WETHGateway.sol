// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressProvider} from "./AddressProvider.sol";
import {ContractsRegister} from "./ContractsRegister.sol";

import {IPoolService} from "../interfaces/IPoolService.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {IWETH} from "../interfaces/external/IWETH.sol";
import {IWETHGateway} from "../interfaces/IWETHGateway.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title WETHGateway
/// @notice Used for converting ETH <> WETH
contract WETHGateway is IWETHGateway {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable wethAddress;
    ContractsRegister internal immutable _contractsRegister;

    // Contract version
    uint256 public constant version = 1;

    event WithdrawETH(address indexed pool, address indexed to);

    /// @dev Checks that pool is registered and underlying token is WETH
    modifier wethPoolOnly(address pool) {
        // Could be optimised by adding internal list of pools
        require(_contractsRegister.isPool(pool), Errors.REGISTERED_POOLS_ONLY); // T:[WG-1]

        require(
            IPoolService(pool).underlying() == wethAddress,
            Errors.WG_DESTINATION_IS_NOT_WETH_COMPATIBLE
        ); // T:[WG-2]
        _;
    }

    /// @dev Checks that credit manager is registered
    modifier creditManagerOnly(address creditManager) {
        // Could be optimised by adding internal list of creditManagers

        require(
            _contractsRegister.isCreditManager(creditManager),
            Errors.REGISTERED_CREDIT_ACCOUNT_MANAGERS_ONLY
        ); // T:[WG-3]

        _;
    }

    //
    // CONSTRUCTOR
    //

    /// @dev Constructor
    /// @param addressProvider Address Repository for upgradable contract model
    constructor(address addressProvider) {
        require(
            addressProvider != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        wethAddress = AddressProvider(addressProvider).getWethToken();
        _contractsRegister = ContractsRegister(
            AddressProvider(addressProvider).getContractsRegister()
        );
    }

    /// @dev convert ETH to WETH and add liqudity to pool
    /// @param pool Address of PoolService contract which where user wants to add liquidity. This pool should has WETH as underlying asset
    /// @param onBehalfOf The address that will receive the diesel tokens, same as msg.sender if the user  wants to receive them on his
    ///                   own wallet, or a different address if the beneficiary of diesel tokens is a different wallet
    /// @param referralCode Code used to register the integrator originating the operation, for potential rewards.
    /// 0 if the action is executed directly by the user, without any middle-man
    function addLiquidityETH(
        address pool,
        address onBehalfOf,
        uint16 referralCode
    )
        external
        payable
        override
        wethPoolOnly(pool) // T:[WG-1, 2]
    {
        IWETH(wethAddress).deposit{value: msg.value}(); // T:[WG-8]

        _checkAllowance(pool, msg.value); // T:[WG-8]
        IPoolService(pool).addLiquidity(msg.value, onBehalfOf, referralCode); // T:[WG-8]
    }

    /// @dev Removes liquidity from pool and convert WETH to ETH
    ///       - burns lp's diesel (LP) tokens
    ///       - returns underlying tokens to lp
    /// @param pool Address of PoolService contract which where user wants to withdraw liquidity. This pool should has WETH as underlying asset
    /// @param amount Amount of tokens to be transfer
    /// @param to Address to transfer liquidity
    function removeLiquidityETH(
        address pool,
        uint256 amount,
        address payable to
    )
        external
        override
        wethPoolOnly(pool) // T:[WG-1, 2]
    {
        IERC20(IPoolService(pool).dieselToken()).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        ); // T: [WG-9]

        uint256 amountGet = IPoolService(pool).removeLiquidity(
            amount,
            address(this)
        ); // T: [WG-9]
        _unwrapWETH(to, amountGet); // T: [WG-9]

        emit WithdrawETH(pool, to);
    }

    /// @dev Converts WETH to ETH, it's used when credit manager sends tokens, and one of them is WETH
    function unwrapWETH(address to, uint256 amount)
        external
        override
        creditManagerOnly(msg.sender) // T:[WG-5]
    {
        _unwrapWETH(to, amount); // T: [WG-7]
    }

    function _unwrapWETH(address to, uint256 amount) internal {
        IWETH(wethAddress).withdraw(amount); // T: [WG-7]
        payable(to).sendValue(amount); // T: [WG-7]
    }

    function _checkAllowance(address spender, uint256 amount) internal {
        if (IERC20(wethAddress).allowance(address(this), spender) < amount) {
            IERC20(wethAddress).approve(spender, type(uint256).max);
        }
    }

    /// @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
    receive() external payable {
        require(
            msg.sender == address(wethAddress),
            Errors.WG_RECEIVE_IS_NOT_ALLOWED
        ); // T:[WG-6]
    }
}
