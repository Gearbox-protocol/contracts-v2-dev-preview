// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "../interfaces/external/IWETH.sol";
import {PercentageMath, PERCENTAGE_FACTOR} from "../libraries/PercentageMath.sol";

/// INTERFACES
import {ICreditFacade, MultiCall} from "../interfaces/ICreditFacade.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IPoolService} from "../interfaces/IPoolService.sol";

// CONSTANTS
import {WAD} from "../libraries/WadRayMath.sol";
import {LEVERAGE_DECIMALS} from "../libraries/Constants.sol";

// EXCEPTIONS
import {ZeroAddressException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

/// @title CreditFacade
/// @notice User interface for interacting with creditManager
/// @dev CreditFacade provide interface to interact with creditManager. Direct interactions
/// with creditManager are forbidden. So, there are two ways how to interact with creditManager:
/// - CreditFacade provides API for accounts management: open / close / liquidate and manage debt
/// - CreditFacade also implements multiCall feature which allows to execute bunch of orders
/// in one transaction and have only one full collateral check
/// - Adapters allow to interact with creditManager directly and implement the same API as orignial protocol
contract CreditFacade is ICreditFacade, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    /// @dev Contracts register to check that credit manager is registered in Gearbox
    ICreditManager public immutable creditManager;

    // underlying is stored here for gas optimisation
    address public immutable underlying;

    // Allowed contracts array
    EnumerableSet.AddressSet private allowedContractsSet;

    // Allowed transfers
    mapping(address => mapping(address => bool))
        public
        override transfersAllowed;

    // Map which keeps contract to adapter (one-to-one) dependency
    mapping(address => address) public override contractToAdapter;

    // Address of WETH token
    address public immutable wethAddress;

    // True if increasing debt is forbidden
    bool public override isIncreaseDebtForbidden;

    // DegenMode - mode, when only whitelisted users can open a credit accounts
    bool public override degenMode;

    // Degens list
    mapping(address => uint256) public override totalOpenedAccountsDegenMode;

    // DegenNFT
    address public immutable degenNFT;

    // Contract version
    uint256 public constant version = 2;

    /// @dev Restricts actions for users with opened credit accounts only
    modifier creditConfiguratorOnly() {
        if (msg.sender != creditManager.creditConfigurator())
            revert CreditConfiguratorOnlyException();

        _;
    }

    /// @dev Initializes creditFacade and connects it with CreditManager
    /// @param _creditManager address of creditManager
    /// @param _degenNFT address if DegenNFT or address(0) if degen mode is not used
    constructor(address _creditManager, address _degenNFT) {
        // Additional check that _creditManager is not address(0)
        if (_creditManager == address(0)) revert ZeroAddressException(); // F:[FA-1]

        creditManager = ICreditManager(_creditManager); // F:[FA-2]
        underlying = ICreditManager(_creditManager).underlying(); // F:[FA-2]
        wethAddress = ICreditManager(_creditManager).wethAddress(); // F:[FA-2]

        degenNFT = _degenNFT;
        degenMode = _degenNFT != address(0);
    }

    // Notice: ETH interaction
    // CreditFacade implements new flow for interacting with WETH. Despite V1, it automatically
    // wraps all provided value into WETH and immidiately sends it to msg.sender.
    // This flow requires allowance in WETH contract to creditManager, however, it makes
    // strategies more flexible, cause there is no need to compute how much ETH should be returned
    // in case it's not used in multicall for example which could be complex.

    /// @dev Opens credit account and provides credit funds as it was done in V1
    /// - Wraps ETH to WETH and sends it msg. sender is value > 0
    /// - Opens credit account (take it from account factory)
    /// - Transfers user initial funds to credit account to use them as collateral
    /// - Transfers borrowed leveraged amount from pool (= amount x leverageFactor) calling lendCreditAccount() on connected Pool contract.
    /// - Emits OpenCreditAccount event
    ///
    /// Function reverts if user has already opened position
    ///
    /// More info: https://dev.gearbox.fi/developers/credit/credit_manager#open-credit-account
    ///
    /// @param amount Borrowers own funds
    /// @param onBehalfOf The address that we open credit account. Same as msg.sender if the user wants to open it for  his own wallet,
    ///  or a different address if the beneficiary is a different wallet
    /// @param leverageFactor Multiplier to borrowers own funds
    /// @param referralCode Referral code which is used for potential rewards. 0 if no referral code provided
    function openCreditAccount(
        uint256 amount,
        address onBehalfOf,
        uint256 leverageFactor,
        uint256 referralCode
    ) external payable override nonReentrant {
        // Checks is it allowed to open credit account
        _isOpenCreditAccountAllowed(onBehalfOf);

        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]

        // borrowedAmount = amount * leverageFactor
        uint256 borrowedAmount = (amount * leverageFactor) / LEVERAGE_DECIMALS; // F:[FA-4]

        // Gets Liquidation threshold for undelying token
        uint256 ltu = creditManager.liquidationThresholds(underlying);

        console.log(ltu);

        // This sanity checks come from idea that hf > 1,
        // which means (amount + borrowedAmount) * LTU > borrowedAmount
        // amount * LTU > borrowedAmount * (1 - LTU)
        if (amount * ltu <= borrowedAmount * (PERCENTAGE_FACTOR - ltu))
            revert IncorrectOpenCreditAccountAmountException();

        // Opens credit accnount and gets its address
        address creditAccount = creditManager.openCreditAccount(
            borrowedAmount,
            onBehalfOf
        ); // F:[FA-4]

        // Emits openCreditAccount event before adding collateral, to make correct order
        emit OpenCreditAccount(
            onBehalfOf,
            creditAccount,
            borrowedAmount,
            referralCode
        ); // F:[FA-4]

        // Adds collateral to new credit account, if it's not revert it means that we have enough
        // collateral on credit account
        creditManager.addCollateral(msg.sender, onBehalfOf, underlying, amount); // F:[FA-4]

        emit AddCollateral(onBehalfOf, underlying, amount); // F;[FA-4]
    }

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
    ) external payable override nonReentrant {
        // Checks is it allowed to open credit account
        _isOpenCreditAccountAllowed(onBehalfOf);

        // It's forbidden to increase debt if increaseDebtForbidden mode is enabled
        // TODO: add test
        if (isIncreaseDebtForbidden) revert IncreaseDebtForbiddenException();

        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]

        address creditAccount = creditManager.openCreditAccount(
            borrowedAmount,
            onBehalfOf
        ); // F:[FA-5]

        // emit new event
        emit OpenCreditAccount(
            onBehalfOf,
            creditAccount,
            borrowedAmount,
            referralCode
        ); // F:[FA-5]

        /// TODO: cover case when user tries to descrease debt during openCreditAccount and reverts
        if (calls.length > 0) _multicall(calls, onBehalfOf, false, true); // F:[FA-5]

        // Checks that new credit account has enough collateral to cover the debt
        creditManager.fullCollateralCheck(creditAccount); // F:[FA-5]
    }

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
    ) external payable override nonReentrant {
        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]

        // Executes multicall operations
        if (calls.length > 0) _multicall(calls, msg.sender, true, false); // F:[FA-6]

        // Closes credit account
        creditManager.closeCreditAccount(
            msg.sender,
            false,
            0,
            msg.sender,
            to,
            skipTokenMask,
            convertWETH
        ); // F:[FA-6]

        emit CloseCreditAccount(msg.sender, to); // F:[FA-6]
    }

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
    ) external payable override nonReentrant {
        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]

        address creditAccount = creditManager.getCreditAccountOrRevert(
            borrower
        ); // T: [CM-9]

        (bool isLiquidatable, uint256 totalValue) = _isAccountLiquidatable(
            creditAccount
        );

        if (!isLiquidatable)
            revert CantLiquidateWithSuchHealthFactorException();

        if (calls.length != 0) _multicall(calls, borrower, true, false); // F:[FA-8]

        // Closes credit account and gets remaiingFunds which were sent to borrower
        uint256 remainingFunds = creditManager.closeCreditAccount(
            borrower,
            true,
            totalValue,
            msg.sender,
            to,
            skipTokenMask,
            convertWETH
        ); // F:[FA-8]

        emit LiquidateCreditAccount(borrower, msg.sender, to, remainingFunds); // F:[FA-8]
    }

    /// @dev Increases debt
    /// - Increase debt by tranferring funds from the pool
    /// - Updates cunulativeIndex to accrued interest rate.
    ///
    /// @param amount Amount to increase borrowed amount
    function increaseDebt(uint256 amount) external override nonReentrant {
        // It's forbidden to take debt by providing any collateral if increaseDebtForbidden mode is enabled
        if (isIncreaseDebtForbidden) revert IncreaseDebtForbiddenException();

        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );
        creditManager.manageDebt(msg.sender, amount, true); // F:[FA-9]

        // Checks that credit account has enough collater to cover new debt paramters
        creditManager.fullCollateralCheck(creditAccount); // F:[FA-9]
        emit IncreaseBorrowedAmount(msg.sender, amount); // F:[FA-9]
    }

    /// @dev Decrease debt
    /// - Decresase debt by paing funds back to pool
    /// - It's also include to this payment interest accrued at the moment and fees
    /// - Updates cunulativeIndex to cumulativeIndex now
    ///
    /// @param amount Amount to increase borrowed amount
    function decreaseDebt(uint256 amount) external override nonReentrant {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        creditManager.manageDebt(msg.sender, amount, false); // F:[FA-10]

        // We need this check, cause after paying debt back, it potentially could be
        // another portfolio structure, which has lower Hf
        creditManager.fullCollateralCheck(creditAccount); // F:[FA-10]
        emit DecreaseBorrowedAmount(msg.sender, amount); // F:[FA-10]
    }

    /// @dev Adds collateral to borrower's credit account
    /// @param onBehalfOf Address of borrower to add funds
    /// @param token Token address, it should be whitelisted on CreditManagert, otherwise it reverts
    /// @param amount Amount to add
    function addCollateral(
        address onBehalfOf,
        address token,
        uint256 amount
    ) external payable override nonReentrant {
        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]

        creditManager.addCollateral(msg.sender, onBehalfOf, token, amount); // F:[FA-11]
        emit AddCollateral(onBehalfOf, token, amount); // F:[FA-11]
    }

    /// @dev Executes a bunch of transactions and then make full collateral check:
    ///  - Wraps ETH and sends it back to msg.sender address, if value > 0
    ///  - Execute bunch of transactions
    ///  - Check that hf > 1 ather this bunch using fullCollateral check
    /// @param calls Multicall structure for calls. Basic usage is to place addCollateral calls to provide collateral in
    ///   assets that differ than undelyring one
    function multicall(MultiCall[] calldata calls)
        external
        payable
        override
        nonReentrant
    {
        // Wraps ETH and sends it back to msg.sender address
        _wrapETH(); // F:[FA-3]
        if (calls.length != 0) {
            address creditAccount = creditManager.getCreditAccountOrRevert(
                msg.sender
            );
            _multicall(calls, msg.sender, false, false);
            creditManager.fullCollateralCheck(creditAccount);
        }
    }

    /// @dev Multicall implementation - executes bunch of transactions
    /// - Transfer ownership from borrower to this contract
    /// - Execute list of calls:
    ///   + if targetContract == address(this), it parses transaction and reroute following functions:
    ///   + addCollateral will be executed as usual. it changes borrower address to creditFacade automatically if needed
    ///   + increaseDebt works as usual
    ///   + decreaseDebt works as usual
    ///   + if targetContract == adapter (allowed, ofc), it would call this adapter. Adapter will skip additional checks
    ///     for this call
    /// @param isIncreaseDebtWasCalled - true if debt was increased during multicall. Used to prevent free freshloans
    /// it's provided as parameter, cause openCreditAccount takes debt itself.
    function _multicall(
        MultiCall[] calldata calls,
        address borrower,
        bool isClosure,
        bool isIncreaseDebtWasCalled
    ) internal {
        // Taking ownership of contract
        creditManager.transferAccountOwnership(borrower, address(this)); // F:[FA-16, 17]

        // Emits event for analytic purposes to track operations which are done on
        emit MultiCallStarted(borrower);

        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ) {
            MultiCall calldata mcall = calls[i];

            // Reverts of calldata has less than 4 bytes
            if (mcall.callData.length < 4)
                revert IncorrectCallDataLengthException(); // F:[FA-12]

            if (mcall.target == address(this)) {
                // No internal calls on closure to avoid loss manipulation
                if (isClosure)
                    revert IntlCallsDuringClosureForbiddenException(); // F:[FA-29, FA-30]
                // Gets method signature to process selected method manually
                bytes4 method = bytes4(mcall.callData);

                //
                //
                // ADD COLLATERAL
                if (method == ICreditFacade.addCollateral.selector) {
                    // Parses parameters
                    (address onBehalfOf, address token, uint256 amount) = abi
                    .decode(mcall.callData[4:], (address, address, uint256)); // F:[FA-16, 16A]

                    //  changes onBehalf of to address(this) automatically  if applicable. It's safe, cause account trasfership were trasffered here.
                    creditManager.addCollateral(
                        msg.sender, // Payer = caller
                        onBehalfOf == borrower ? address(this) : onBehalfOf,
                        token,
                        amount
                    ); // F:[FA-16, 16A]

                    // Emits event with original onBehalfOf, cause address(this) has no sense
                    emit AddCollateral(onBehalfOf, token, amount); // F:[FA-16, 16A]
                }
                //
                //
                // INCREASE DEBT
                else if (method == ICreditFacade.increaseDebt.selector) {
                    // It's forbidden to increase debt if increaseDebtForbidden mode is enabled
                    // TODO: add test
                    if (isIncreaseDebtForbidden)
                        revert IncreaseDebtForbiddenException();
                    // Parses parameters
                    uint256 amount = abi.decode(mcall.callData[4:], (uint256)); // F:[FA-16]

                    // Executes manageDebt method onBehalf of address
                    creditManager.manageDebt(address(this), amount, true); // F:[FA-16]
                    emit IncreaseBorrowedAmount(borrower, amount); // F:[FA-16]
                    isIncreaseDebtWasCalled = true;
                }
                //
                //
                // DECREASE DEBT
                else if (method == ICreditFacade.decreaseDebt.selector) {
                    // it's forbidden to call descrease debt in the same multicall, where increaseDebt was called
                    if (isIncreaseDebtWasCalled)
                        revert IncreaseAndDecreaseForbiddenInOneCallException();
                    // F:[FA-32]

                    // Parses parameters
                    uint256 amount = abi.decode(mcall.callData[4:], (uint256)); // F:[FA-16A]

                    // Executes manageDebt method onBehalf of address(this)
                    creditManager.manageDebt(address(this), amount, false); // F:[FA-16A]
                    emit DecreaseBorrowedAmount(borrower, amount); // F:[FA-16A]
                } else {
                    // Reverts for unknown method
                    revert UnknownMethodException(); // [FA-13]
                }
            } else {
                //
                //
                // ADAPTERS

                // It double checks that call is not addressed to creditManager
                // This contract has powerfull permissons and .functionCall() to creditManager forbidden
                // Even if Configurator would add it as legal ADAPTER
                if (mcall.target == address(creditManager))
                    revert CreditManagerCallsForbiddenException(); // F:[FA-14]

                // Checks that target is allowed adapter
                if (creditManager.adapterToContract(mcall.target) == address(0))
                    revert TargetIsNotAdapterException(); // F:[FA-15]

                // Makes a call
                mcall.target.functionCall(mcall.callData); // F:[FA-17]
            }

            unchecked {
                i++;
            }
        }

        // Emits event for analytic that multicall is ended
        emit MultiCallFinished();

        // Returns transfership back
        creditManager.transferAccountOwnership(address(this), borrower); // F:[FA-16, 17]
    }

    /// @dev Approves token of credit account for 3rd party contract
    /// @param targetContract Contract to check allowance
    /// @param token Token address of contract
    /// @param amount Amount to approve
    function approve(
        address targetContract,
        address token,
        uint256 amount
    ) external override nonReentrant {
        // Checks that targetContract is allowed - it has non-zero address adapter
        if (contractToAdapter[targetContract] == address(0))
            revert ContractNotAllowedException(); // F:[FA-18]

        // Checks that the token is allowed
        if (!isTokenAllowed(token)) revert TokenNotAllowedException(); // F:[FA-18]
        creditManager.approveCreditAccount(
            msg.sender,
            targetContract,
            token,
            amount
        ); // F:[FA-19]
    }

    /// @dev Transfers credit account to another user
    /// By default, this action is forbidden, and the user should allow sender to do that
    /// by calling approveAccountTransfers function.
    /// The logic for this approval is to eliminate sending "bad debt" to someone, who unexpect this.
    /// @param to Address which will get an account
    function transferAccountOwnership(address to) external override {
        // Checks that transfer is allowed
        if (!transfersAllowed[msg.sender][to])
            revert AccountTransferNotAllowedException(); // F:[FA-20]

        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        ); // TODO: test

        // TODO: add test that transferring account with hf<1 is forbidden
        (bool isLiquidatable, ) = _isAccountLiquidatable(creditAccount);

        if (isLiquidatable) revert CantTransferLiquidatableAccountException();

        // Transfer account an emits event
        creditManager.transferAccountOwnership(msg.sender, to); // F:[FA-21]
        emit TransferAccount(msg.sender, to); // F:[FA-21]
    }

    /// @dev Checks is it allowed to open credit account
    /// @param onBehalfOf Account which would own credit account
    function _isOpenCreditAccountAllowed(address onBehalfOf) internal {
        // Check that onBehalfOf could open credit account in DegenMode
        // It takes 2K of gas to read degenMode value, comment this line
        // and in openCreditAccountMulticall if degen mode is not needed

        // TODO: add tests here
        if (degenMode) {
            uint256 balance = ERC721(degenNFT).balanceOf(onBehalfOf);

            // Checks that address has already opened account in the past
            if (totalOpenedAccountsDegenMode[onBehalfOf] >= balance) {
                revert HasAlreadyOpenedCreditAccountInDegenMode();
            }

            // Sets flag that address has opened credit account
            totalOpenedAccountsDegenMode[onBehalfOf]++;
        }

        /// Cheks that user opens credit account for himself otherwise it has allowance for account transfer
        if (
            msg.sender != onBehalfOf &&
            !transfersAllowed[msg.sender][onBehalfOf]
        ) revert AccountTransferNotAllowedException(); // F:[FA-31]
    }

    /// @dev Approves transfer account from some particular user
    /// @param from Address which allows/forbids credit account transfer
    /// @param state True is transfer is allowed, false to be borbidden
    function approveAccountTransfers(address from, bool state)
        external
        override
    {
        transfersAllowed[from][msg.sender] = state; // F:[FA-22]
        emit TransferAccountAllowed(from, msg.sender, state); // F:[FA-22]
    }

    //
    // GETTERS
    //

    /// @dev Returns true if tokens allowed otherwise false
    function isTokenAllowed(address token)
        public
        view
        override
        returns (bool allowed)
    {
        uint256 tokenMask = creditManager.tokenMasksMap(token); // F:[FA-23]
        allowed =
            (tokenMask > 0) &&
            (creditManager.forbidenTokenMask() & tokenMask == 0); // F:[FA-2]
    }

    /// @dev Calculates total value for provided address in underlying asset
    /// More: https://dev.gearbox.fi/developers/credit/economy#total-value
    ///
    /// @param creditAccount Token creditAccount address
    /// @return total Total value
    /// @return twv Total weighted value
    function calcTotalValue(address creditAccount)
        public
        view
        override
        returns (uint256 total, uint256 twv)
    {
        IPriceOracle priceOracle = IPriceOracle(creditManager.priceOracle()); // F:[FA-24]

        uint256 tokenMask;
        uint256 eTokens = creditManager.enabledTokensMap(creditAccount); // F:[FA-24]
        uint256 count = creditManager.allowedTokensCount(); // F:[FA-24]
        for (uint256 i = 0; i < count; ) {
            tokenMask = 1 << i; // F:[FA-24]
            if (eTokens & tokenMask > 0) {
                address token = creditManager.allowedTokens(i);
                uint256 balance = IERC20(token).balanceOf(creditAccount); // F:[FA-24]

                if (balance > 1) {
                    uint256 value = priceOracle.convertToUSD(balance, token); // F:[FA-24]

                    unchecked {
                        total += value; // F:[FA-24]
                    }
                    twv += value * creditManager.liquidationThresholds(token); // F:[FA-24]
                }
            } // T:[FA-17]

            unchecked {
                ++i;
            }
        }

        total = priceOracle.convertFromUSD(total, underlying); // F:[FA-24]
        twv = priceOracle.convertFromUSD(twv, underlying) / PERCENTAGE_FACTOR; // F:[FA-24]
    }

    /**
     * @dev Calculates health factor for the credit account
     *
     *         sum(asset[i] * liquidation threshold[i])
     *   Hf = --------------------------------------------
     *             borrowed amount + interest accrued
     *
     *
     * More info: https://dev.gearbox.fi/developers/credit/economy#health-factor
     *
     * @param creditAccount Credit account address
     * @return hf = Health factor in percents (see PERCENTAGE FACTOR in PercentageMath.sol)
     */
    function calcCreditAccountHealthFactor(address creditAccount)
        public
        view
        override
        returns (uint256 hf)
    {
        (, uint256 twv) = calcTotalValue(creditAccount); // F:[FA-25]
        (, uint256 borrowAmountWithInterest) = creditManager
        .calcCreditAccountAccruedInterest(creditAccount); // F:[FA-25]
        hf = (twv * PERCENTAGE_FACTOR) / borrowAmountWithInterest; // F:[FA-25]
    }

    /// @dev Returns true if the borrower has opened a credit account
    /// @param borrower Borrower account
    function hasOpenedCreditAccount(address borrower)
        public
        view
        override
        returns (bool)
    {
        return creditManager.creditAccounts(borrower) != address(0); // F:[FA-26]
    }

    /// @dev Wraps ETH into WETH and sends it back to msg.sender
    function _wrapETH() internal {
        if (msg.value > 0) {
            IWETH(wethAddress).deposit{value: msg.value}(); // F:[FA-3]
            IWETH(wethAddress).transfer(msg.sender, msg.value); // F:[FA-3]
        }
    }

    /// @dev Checks if account is liquidatable
    /// @param creditAccount Address of credit account to check
    /// @return isLiquidatable True if account could be liquidated
    /// @return totalValue Portfolio value
    function _isAccountLiquidatable(address creditAccount)
        internal
        view
        returns (bool isLiquidatable, uint256 totalValue)
    {
        uint256 twv;
        // transfers assets to "to" address and compute total value (tv) & threshold weighted value (twv)
        (totalValue, twv) = calcTotalValue(creditAccount); // F:[FA-7]

        (, uint256 borrowAmountWithInterest) = creditManager
        .calcCreditAccountAccruedInterest(creditAccount); // F:[FA-7]

        // Checks that current Hf < 1
        isLiquidatable = twv < borrowAmountWithInterest;
    }

    //
    // CONFIGURATION
    //

    /// @dev Adds / Removes Allowed adapter
    /// @param _adapter Adapter addrss
    /// @param _contract Target contract address if it's need to be set, address(0) to remove adapter from allowed list
    function setContractToAdapter(address _adapter, address _contract)
        external
        creditConfiguratorOnly // F:[FA-27]
    {
        contractToAdapter[_contract] = _adapter; // F:[FA-28]
    }

    function setDegenMode(bool _mode) external creditConfiguratorOnly {
        degenMode = _mode;
    }

    function setIncreaseDebtForbidden(bool _mode)
        external
        creditConfiguratorOnly
    {
        isIncreaseDebtForbidden = _mode;
    }
}
