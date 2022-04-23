// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {AbstractAdapter} from "../AbstractAdapter.sol";
import {IAdapter, AdapterType} from "../../interfaces/adapters/IAdapter.sol";
import {ICreditManager} from "../../interfaces/ICreditManager.sol";
import {ICreditFacade} from "../../interfaces/ICreditFacade.sol";

import {IYVault} from "../../integrations/yearn/IYVault.sol";

import {CreditAccount} from "../../credit/CreditAccount.sol";
import {CreditManager} from "../../credit/CreditManager.sol";

// EXCEPTIONS
import {NotImplementedException} from "../../interfaces/IErrors.sol";
import {ICreditManagerExceptions} from "../../interfaces/ICreditManager.sol";

/// @title Yearn adapter
contract YearnV2Adapter is AbstractAdapter, IYVault, ReentrancyGuard {
    address public immutable override token;

    AdapterType public constant _gearboxAdapterType = AdapterType.YEARN_V2;
    uint16 public constant _gearboxAdapterVersion = 2;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _yVault Address of YEARN vault contract
    constructor(address _creditManager, address _yVault)
        AbstractAdapter(_creditManager, _yVault)
    {
        // Check that we have token connected with this yearn pool
        token = IYVault(targetContract).token(); // F:[AYV2-2]
        if (!ICreditFacade(creditFacade).isTokenAllowed(token))
            revert ICreditManagerExceptions.TokenNotAllowedException(); // F:[AYV2-3]
    }

    /// @dev Deposit credit account tokens to Yearn
    function deposit() external override nonReentrant returns (uint256) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return
            _deposit(creditAccount, IERC20(token).balanceOf(creditAccount) - 1); // F:[AYV2-5,10]
    }

    /// @dev Deposit credit account tokens to Yearn
    /// @param amount in tokens
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        returns (uint256)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return _deposit(creditAccount, amount); // F:[AYV2-6,11]
    }

    /// @dev Deposit credit account tokens to Yearn
    /// @param amount in tokens
    function deposit(uint256 amount, address)
        external
        override
        nonReentrant
        returns (uint256)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return _deposit(creditAccount, amount); // F:[AYV2-7,12]
    }

    function _deposit(address creditAccount, uint256 amount)
        internal
        returns (uint256 shares)
    {
        shares = abi.decode(
            _executeFastCheck(
                creditAccount,
                token,
                targetContract,
                abi.encodeWithSelector(bytes4(0xb6b55f25), amount),
                true
            ),
            (uint256)
        ); // F:[AYV2-5,6,7,10,11,12]
    }

    function withdraw() external override nonReentrant returns (uint256) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        uint256 maxShares = IERC20(targetContract).balanceOf(creditAccount) - 1; // F:[AYV2-8, 13]
        return _withdraw(creditAccount, maxShares); // F:[AYV2-8, 13]
    }

    function withdraw(uint256 maxShares)
        external
        override
        nonReentrant
        returns (uint256)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return _withdraw(creditAccount, maxShares); // F:[AYV2-9, 14]
    }

    function withdraw(uint256 maxShares, address)
        external
        override
        nonReentrant
        returns (uint256)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return _withdraw(creditAccount, maxShares); // F:[AYV2-9,14]
    }

    /// @dev Withdraw yVaults from credit account
    /// @param maxShares How many shares to try and redeem for tokens, defaults to all.
    //  @param recipient The address to issue the shares in this Vault to. Defaults to the caller's address.
    //  @param maxLoss The maximum acceptable loss to sustain on withdrawal. Defaults to 0.01%.
    //                 If a loss is specified, up to that amount of shares may be burnt to cover losses on withdrawal.
    //  @return The quantity of tokens redeemed for `_shares`.
    function withdraw(
        uint256 maxShares,
        address,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256 shares) {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // F:[AYV2-4]

        return _withdraw(creditAccount, maxShares); // F:[AYV2-9,14]
    }

    function _withdraw(address creditAccount, uint256 maxShares)
        internal
        returns (uint256 shares)
    {
        shares = abi.decode(
            _executeFastCheck(
                creditAccount,
                targetContract,
                token,
                abi.encodeWithSelector(bytes4(0x2e1a7d4d), maxShares),
                false
            ),
            (uint256)
        ); // F:[AYV2-8,9,13,14]
    }

    function pricePerShare() external view override returns (uint256) {
        return IYVault(targetContract).pricePerShare();
    }

    function name() external view override returns (string memory) {
        return IYVault(targetContract).name();
    }

    function symbol() external view override returns (string memory) {
        return IYVault(targetContract).symbol();
    }

    function decimals() external view override returns (uint8) {
        return IYVault(targetContract).decimals();
    }

    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return IYVault(targetContract).allowance(owner, spender);
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return IYVault(targetContract).balanceOf(account);
    }

    function totalSupply() external view override returns (uint256) {
        return IYVault(targetContract).totalSupply();
    }

    function transfer(address, uint256) external pure override returns (bool) {
        revert NotImplementedException();
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure override returns (bool) {
        revert NotImplementedException();
    }
}
