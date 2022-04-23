// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ICreditManager} from "./ICreditManager.sol";

struct MultiCall {
    address target;
    bytes callData;
}

interface ICreditFacadeEvents {
    // Emits each time when the credit account is opened
    event OpenCreditAccount(
        address indexed onBehalfOf,
        address indexed creditAccount,
        uint256 borrowAmount,
        uint256 referralCode
    );

    // Emits each time when the credit account is repaid
    event CloseCreditAccount(address indexed owner, address indexed to);

    // Emits each time when the credit account is liquidated
    event LiquidateCreditAccount(
        address indexed owner,
        address indexed liquidator,
        address indexed to,
        uint256 remainingFunds
    );

    // Emits each time when borrower increases borrowed amount
    event IncreaseBorrowedAmount(address indexed borrower, uint256 amount);

    // Emits each time when borrower increases borrowed amount
    event DecreaseBorrowedAmount(address indexed borrower, uint256 amount);

    // Emits each time when borrower adds collateral
    event AddCollateral(
        address indexed onBehalfOf,
        address indexed token,
        uint256 value
    );

    // Emits each time when multicall is started
    event MultiCallStarted(address indexed borrower);

    // Emits each time when multicall is finished
    event MultiCallFinished();

    // Emits each time when credit account is transfered
    event TransferAccount(address indexed oldOwner, address indexed newOwner);

    event TransferAccountAllowed(
        address indexed from,
        address indexed to,
        bool state
    );
}

interface ICreditFacadeExceptions {
    error NoDegenNFTInDegenModeException();

    error HasAlreadyOpenedCreditAccountInDegenMode();

    error AccountTransferNotAllowedException();

    error IncorrectOpenCreditAccountAmountException();

    /// @dev throws if try to liquidate credit account with Hf > 1
    error CantLiquidateWithSuchHealthFactorException();

    error IncorrectCallDataLengthException();

    error IntlCallsDuringClosureForbiddenException();

    error IncreaseAndDecreaseForbiddenInOneCallException();

    error UnknownMethodException();

    error CreditManagerCallsForbiddenException();

    error TargetIsNotAdapterException();

    error ContractNotAllowedException();

    error TokenNotAllowedException();

    error CreditConfiguratorOnlyException();

    /// @dev throws if user runs openCredeitAccountMulticall or tries to increase borrowed amount when it's forbidden
    error IncreaseDebtForbiddenException();

    /// @dev throws if user thies to transfer credit account with hf < 1;
    error CantTransferLiquidatableAccountException();
}

/// @title Credit Facade interface
/// @notice It encapsulates business logic for managing credit accounts
///
/// More info: https://dev.gearbox.fi/developers/credit/credit_manager
interface ICreditFacade is ICreditFacadeEvents, ICreditFacadeExceptions {
    //
    // CREDIT ACCOUNT MANAGEMENT
    //

    /**
     * @dev Opens credit account and provides credit funds.
     * - Opens credit account (take it from account factory)
     * - Transfers trader /farmers initial funds to credit account
     * - Transfers borrowed leveraged amount from pool (= amount x leverageFactor) calling lendCreditAccount() on connected Pool contract.
     * - Emits OpenCreditAccount event
     * Function reverts if user has already opened position
     *
     * More info: https://dev.gearbox.fi/developers/credit/credit_manager#open-credit-account
     *
     * @param amount Borrowers own funds
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param leverageFactor Multiplier to borrowers own funds
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     */
    function openCreditAccount(
        uint256 amount,
        address onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    ) external payable;

    /// @dev Opens credit account and run a bunch of transactions for multicall
    /// - Opens credit account with desired borrowed amount
    /// - Executes multicall functions for it
    /// - Checks that the new account has enough collateral
    /// - Emits OpenCreditAccount event
    ///
    /// @param borrowedAmount Debt size
    /// @param onBehalfOf The address that we open credit account. Same as msg.sender if the user wants to open it for  his own wallet,
    ///   or a different address if the beneficiary is a different wallet
    /// @param calls Multicall structure for calls. Basic usage is to place addCollateral calls to provide collateral in
    ///   assets that differ than undelyring one
    /// @param referralCode Referral code which is used for potential rewards. 0 if no referral code provided

    function openCreditAccountMulticall(
        uint256 borrowedAmount,
        address onBehalfOf,
        MultiCall[] calldata calls,
        uint256 referralCode
    ) external payable;

    /// @dev Run a bunch of transactions for multicall and then close credit account
    /// - Wraps ETH to WETH and sends it msg.sender is value > 0
    /// - Executes multicall functions for it (the main function is to swap all assets into undelying one)
    /// - Close credit account:
    ///    + It checks underlying token balance, if it > than funds need to be paid to pool, the debt is paid
    ///      by funds from creditAccount
    ///    + if there is no enough funds in credit Account, it withdraws all funds from credit account, and then
    ///      transfers the diff from msg.sender address
    ///    + Then, if sendAllAssets is true, it transfers all non-zero balances from credit account to address "to"
    ///    + If convertWETH is true, the function converts WETH into ETH on the fly
    /// - Emits CloseCreditAccount event
    ///
    /// @param to Address to send funds during closing contract operation
    /// @param skipTokenMask Tokenmask contains 1 for tokens which needed to be skipped for sending
    /// @param convertWETH It true, it converts WETH token into ETH when sends it to "to" address
    /// @param calls Multicall structure for calls. Basic usage is to place addCollateral calls to provide collateral in
    ///   assets that differ than undelyring one
    function closeCreditAccount(
        address to,
        uint256 skipTokenMask,
        bool convertWETH,
        MultiCall[] calldata calls
    ) external payable;

    /// @dev Run a bunch of transactions (multicall) and then liquidate credit account
    /// - Wraps ETH to WETH and sends it msg.sender (liquidator) is value > 0
    /// - It checks that hf < 1, otherwise it reverts
    /// - It computes the amount which should be paid back: borrowed amount + interest + fees
    /// - Executes multicall functions for it (the main function is to swap all assets into undelying one)
    /// - Close credit account:
    ///    + It checks underlying token balance, if it > than funds need to be paid to pool, the debt is paid
    ///      by funds from creditAccount
    ///    + if there is no enough funds in credit Account, it withdraws all funds from credit account, and then
    ///      transfers the diff from msg.sender address
    ///    + Then, if sendAllAssets is false, it transfers all non-zero balances from credit account to address "to".
    ///      Otherwise no transfers would be made. If liquidator is confident that all assets were transffered
    ///      During multicall, this option could save gas costs.
    ///    + If convertWETH is true, the function converts WETH into ETH on the fly
    /// - Emits LiquidateCreditAccount event
    ///
    /// @param to Address to send funds during closing contract operation
    /// @param skipTokenMask Tokenmask contains 1 for tokens which needed to be skipped for sending
    /// @param convertWETH It true, it converts WETH token into ETH when sends it to "to" address
    /// @param calls Multicall structure for calls. Basic usage is to place addCollateral calls to provide collateral in
    ///   assets that differ than undelyring one
    function liquidateCreditAccount(
        address borrower,
        address to,
        uint256 skipTokenMask,
        bool convertWETH,
        MultiCall[] calldata calls
    ) external payable;

    /// @dev Increases debt
    /// - Increase debt by tranferring funds from the pool
    /// - Updates cunulativeIndex to accrued interest rate.
    ///
    /// @param amount Amount to increase borrowed amount
    function increaseDebt(uint256 amount) external;

    /// @dev Decrease debt
    /// - Decresase debt by paing funds back to pool
    /// - It's also include to this payment interest accrued at the moment and fees
    /// - Updates cunulativeIndex to cumulativeIndex now
    ///
    /// @param amount Amount to increase borrowed amount
    function decreaseDebt(uint256 amount) external;

    /// @dev Adds collateral to borrower's credit account
    /// @param onBehalfOf Address of borrower to add funds
    /// @param token Token address
    /// @param amount Amount to add
    function addCollateral(
        address onBehalfOf,
        address token,
        uint256 amount
    ) external payable;

    function multicall(MultiCall[] calldata calls) external payable;

    /// @dev Returns true if the borrower has opened a credit account
    /// @param borrower Borrower account
    function hasOpenedCreditAccount(address borrower)
        external
        view
        returns (bool);

    /// @dev Approves token of credit account for 3rd party contract
    /// @param targetContract Contract to check allowance
    /// @param token Token address of contract
    /// @param amount Amount to approve
    function approve(
        address targetContract,
        address token,
        uint256 amount
    ) external;

    function approveAccountTransfers(address from, bool state) external;

    /// @dev Transfers credit account to another user
    /// By default, this action is forbidden, and the user should allow sender to do that
    /// by calling approveAccountTransfers function.
    /// The logic for this approval is to eliminate sending "bad debt" to someone, who unexpect this.
    /// @param to Address which will get an account
    function transferAccountOwnership(address to) external;

    //
    // GETTERS
    //

    /// @dev Calculates total value for provided address in underlying asset
    ///
    /// @param creditAccount Token creditAccount address
    /// @return total Total value
    /// @return twv Total weighted value
    function calcTotalValue(address creditAccount)
        external
        view
        returns (uint256 total, uint256 twv);

    /// @return hf Health factor for particular credit account
    function calcCreditAccountHealthFactor(address creditAccount)
        external
        view
        returns (uint256 hf);

    /// @return True if tokens allowed otherwise false
    function isTokenAllowed(address token) external view returns (bool);

    /// @return CreditManager connected wit Facade
    function creditManager() external view returns (ICreditManager);

    /// @return Address of adapter connected with address, otherwise address(0)
    function contractToAdapter(address) external view returns (address);

    // @return True if 'from' account is allowed to transfer credit account to 'to' address
    function transfersAllowed(address from, address to)
        external
        view
        returns (bool);

    /// @return True if increasing debt is forbidden
    function isIncreaseDebtForbidden() external view returns (bool);

    /// @return True if degenMode is enabled (special mode, when only whitelisted users can open a credit accounts)
    function degenMode() external view returns (bool);

    // Checks if degen has already opened account [In degen mode you can open credit account not more that your DegenNFT balance]
    function totalOpenedAccountsDegenMode(address)
        external
        view
        returns (uint256);

    // Address of Degen NFT. Each account with balance > 1 has access to degen mode
    function degenNFT() external view returns (address);
}
