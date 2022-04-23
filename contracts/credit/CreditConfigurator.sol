// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2022
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// LIBRARIES & CONSTANTS
import {DEFAULT_FEE_INTEREST, DEFAULT_FEE_LIQUIDATION, DEFAULT_LIQUIDATION_PREMIUM, DEFAULT_CHI_THRESHOLD, DEFAULT_HF_CHECK_INTERVAL} from "../libraries/Constants.sol";
import {WAD} from "../libraries/WadRayMath.sol";
import {PercentageMath, PERCENTAGE_FACTOR} from "../libraries/PercentageMath.sol";

import {ACLTrait} from "../core/ACLTrait.sol";
import {CreditFacade} from "./CreditFacade.sol";
import {CreditManager} from "./CreditManager.sol";

// INTERFACES
import {ICreditConfigurator, AllowedToken, CreditManagerOpts} from "../interfaces/ICreditConfigurator.sol";
import {IAdapter} from "../interfaces/adapters/IAdapter.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IPoolService} from "../interfaces/IPoolService.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";

// EXCEPTIONS
import {ZeroAddressException} from "../interfaces/IErrors.sol";
import {ICreditManagerExceptions} from "../interfaces/ICreditManager.sol";

import "hardhat/console.sol";

/// @title CreditConfigurator
/// @notice This contract is designed for credit managers configuration
/// @dev All functions could be executed by Configurator role only.
/// CreditManager is desing to trust all settings done by CreditConfigurator,
/// so all sanity checks implemented here.
contract CreditConfigurator is ICreditConfigurator, ACLTrait {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Address provider (needed for priceOracle update)
    IAddressProvider public addressProvider;

    /// @dev Address of creditFacade
    CreditFacade public creditFacade;

    /// @dev Address of credit Manager
    CreditManager public creditManager;

    /// @dev Address of underlying token
    address public underlying;

    // Allowed contracts array
    EnumerableSet.AddressSet private allowedContractsSet;

    // Contract version
    uint256 public constant version = 2;

    /// @dev Constructs has special role in credit management deployment
    /// It makes initial configuration for the whole bunch of contracts.
    /// The correct deployment flow is following:
    ///
    /// 1. Configures CreditManager parameters
    /// 2. Adds allowed tokens and set LT for underlying asset
    /// 3. Connects creditFacade and priceOracle with creditManager
    /// 4. Set this contract as configurator for creditManager
    ///
    /// @param _creditManager CreditManager contract instance
    /// @param _creditFacade CreditFacade contract instance
    /// @param opts Configuration parameters for CreditManager
    constructor(
        CreditManager _creditManager,
        CreditFacade _creditFacade,
        CreditManagerOpts memory opts
    )
        ACLTrait(
            address(
                IPoolService(_creditManager.poolService()).addressProvider()
            )
        )
    {
        /// Sets contract addressees
        creditManager = _creditManager; // F:[CC-1]
        creditFacade = _creditFacade; // F:[CC-1]
        underlying = creditManager.underlying(); // F:[CC-1]

        addressProvider = IPoolService(_creditManager.poolService())
            .addressProvider(); // F:[CC-1]

        /// Sets limits, fees and fastCheck parameters for credit manager
        _setParams(
            opts.minBorrowedAmount,
            opts.maxBorrowedAmount,
            DEFAULT_FEE_INTEREST,
            DEFAULT_FEE_LIQUIDATION,
            PERCENTAGE_FACTOR - DEFAULT_LIQUIDATION_PREMIUM,
            DEFAULT_CHI_THRESHOLD,
            DEFAULT_HF_CHECK_INTERVAL
        ); // F:[CC-1]

        /// Adds allowed tokens and sets their liquidation threshold
        /// allowedTokens should not have underlying in the list
        uint256 len = opts.allowedTokens.length;
        for (uint256 i = 0; i < len; ) {
            address token = opts.allowedTokens[i].token;

            _addTokenToAllowedList(token); // F:[CC-1]

            _setLiquidationThreshold(
                token,
                opts.allowedTokens[i].liquidationThreshold
            ); // F:[CC-1]

            unchecked {
                ++i;
            }
        }

        // Connects creditFacade and sets proper priceOracle
        creditManager.upgradeContracts(
            address(_creditFacade),
            address(creditManager.priceOracle())
        ); // F:[CC-1]
    }

    //
    // CONFIGURATION: TOKEN MANAGEMENT
    //

    /// @dev Adds token to the list of allowed tokens, revers if token is already added
    /// @param token Address of token to be added
    function addTokenToAllowedList(address token)
        external
        override
        configuratorOnly // F:[CC-2]
    {
        _addTokenToAllowedList(token);
    }

    /// @dev Makes all sanity checks and adds token to allowed token list
    /// @param token Address of token to be added
    function _addTokenToAllowedList(address token) internal {
        // Checks that token != address(0)
        if (token == address(0)) revert ZeroAddressException(); // F:[CC-3]

        // Checks that contract has balanceOf method
        try IERC20(token).balanceOf(address(this)) returns (uint256) {} catch {
            revert IncorrectTokenContractException(); // F:[CC-3]
        }

        // Checks that token has priceFeed in priceOracle
        try
            IPriceOracle(creditManager.priceOracle()).convertToUSD(WAD, token)
        returns (uint256) {} catch {
            revert IncorrectPriceFeedException(); // F:[CC-3]
        }

        // Calls addToken in creditManager, cause all sanity checks are done
        // creditManager has additional check that the token is not added yet
        creditManager.addToken(token); // F:[CC-4]

        emit TokenAllowed(token); // F:[CC-4]
    }

    /// @dev Set Liquidation threshold for any token except underlying one
    /// @param token Token address except underlying token
    /// @param liquidationThreshold in PERCENTAGE_FORMAT (x10.000)
    function setLiquidationThreshold(
        address token,
        uint256 liquidationThreshold
    )
        external
        configuratorOnly // F:[CC-2]
    {
        _setLiquidationThreshold(token, liquidationThreshold); // F:[CC-5,6]
    }

    /// @dev IMPLEMENTAION: Set Liquidation threshold for any token except underlying one
    /// @param token Token address except underlying token
    /// @param liquidationThreshold in PERCENTAGE_FORMAT (x10.000)
    function _setLiquidationThreshold(
        address token,
        uint256 liquidationThreshold
    ) internal {
        // Checks that token is not undelrying, which could not be set up directly.
        // Instead of that, it updates automatically, when creditManager parameters updated
        if (token == underlying) revert SetLTForUnderlyingException(); // F:[CC-5]

        // Sanity checks for liquidation threshold. It should be >0 and less than LT for underlying token
        if (
            liquidationThreshold == 0 ||
            liquidationThreshold >
            creditManager.liquidationThresholds(underlying)
        ) revert IncorrectLiquidationThresholdException(); // F:[CC-5]

        // It sets it in creditManager, which has additional sanity check that token exists
        creditManager.setLiquidationThreshold(token, liquidationThreshold); // F:[CC-6]
        emit TokenLiquidationThresholdUpdated(token, liquidationThreshold); // F:[CC-6]
    }

    /// @dev Allow already added token if it was forbidden before.
    /// Technically it just updates forbidmask variable which is used to detect forbidden tokens.
    /// @param token Address of allowed token
    function allowToken(address token)
        external
        configuratorOnly // F:[CC-2]
    {
        // Gets tokenMask for particular token
        uint256 tokenMask = creditManager.tokenMasksMap(token);

        // Gets current forbidden mask
        uint256 forbidenTokenMask = creditManager.forbidenTokenMask();

        // It checks that provided token is added to allowedToken list
        // It requires tokenMask !=0 && tokenMask != 1, cause underlying's mask is 1,
        // and underlying token could not be forbidden
        if (tokenMask == 0 || tokenMask == 1)
            revert ICreditManagerExceptions.TokenNotAllowedException(); // F:[CC-7]

        // It change forbid mask in case if the token was forbidden before
        // otherwise no actions done.
        // Skipping case: F:[CC-8]
        if (forbidenTokenMask & tokenMask > 0) {
            forbidenTokenMask ^= tokenMask; // F:[CC-9]
            creditManager.setForbidMask(forbidenTokenMask); // F:[CC-9]
            emit TokenAllowed(token); // F:[CC-9]
        }
    }

    /// @dev Forbids particular token. To allow token one more time use allowToken function
    /// Forbidden tokens are counted as portfolio, however, all operations which could give
    /// them as result are forbidden. Btw, it's still possible to tranfer them directly to
    /// creditAccount however, you can't swap into them directly using creditAccount funds.
    /// @param token Address of forbidden token
    function forbidToken(address token)
        external
        configuratorOnly // F:[CC-2]
    {
        // Gets tokenMask for particular token
        uint256 tokenMask = creditManager.tokenMasksMap(token);

        // Gets current forbidden mask
        uint256 forbidenTokenMask = creditManager.forbidenTokenMask();

        // It checks that provided token is added to allowedToken list
        // It requires tokenMask !=0 && tokenMask != 1, cause underlying's mask is 1,
        // and underlying token could not be forbidden
        if (tokenMask == 0 || tokenMask == 1)
            revert ICreditManagerExceptions.TokenNotAllowedException(); // F:[CC-7]

        // It changes forbidenTokenMask if token is allowed at the moment only
        // Skipping case: F:[CC-10]
        if (forbidenTokenMask & tokenMask == 0) {
            forbidenTokenMask |= tokenMask; // F:[CC-11]
            creditManager.setForbidMask(forbidenTokenMask); // F:[CC-11]
            emit TokenForbidden(token); // F:[CC-11]
        }
    }

    //
    // CONFIGURATION: CONTRACTS & ADAPTERS MANAGEMENT
    //

    /// @dev Adds pair [contract <-> adapter] to the list of allowed contracts
    /// or updates adapter addreess if contract already has connected adapter
    /// @param targetContract Address of allowed contract
    /// @param adapter Adapter contract address
    function allowContract(address targetContract, address adapter)
        external
        override
        configuratorOnly // F:[CC-2]
    {
        _allowContract(targetContract, adapter);
    }

    /// @dev IMPLEMENTATION: Adds pair [contract <-> adapter] to the list of allowed contracts
    /// or updates adapter addreess if contract already has connected adapter
    /// @param targetContract Address of allowed contract
    /// @param adapter Adapter contract address
    function _allowContract(address targetContract, address adapter) internal {
        // Checks that targetContract or adapter != address(0)
        if (targetContract == address(0) || adapter == address(0))
            revert ZeroAddressException(); // F:[CC-12]

        // Additional check that adapter or targetContract is not
        // creditManager or creditFacade.
        // This additional check, cause call on behalf creditFacade to creditManager
        // cause it could have unexpected consequences
        if (
            targetContract == address(creditManager) ||
            targetContract == address(creditFacade) ||
            adapter == address(creditManager) ||
            adapter == address(creditFacade)
        ) revert CreditManagerOrFacadeUsedAsAllowContractsException(); // F:[CC-13]

        // Checks that adapter or targetContract is not used in any other case
        if (
            creditManager.adapterToContract(adapter) != address(0) ||
            creditFacade.contractToAdapter(targetContract) != address(0)
        ) revert AdapterUsedTwiceException(); // F:[CC-14]

        // Checks that adapter has the same creditManager as we'd like to connect
        if (IAdapter(adapter).creditManager() != creditManager)
            revert AdapterHasIncorrectCreditManagerException(); // F:[CC-30]

        // Sets link adapter <-> targetContract to creditFacade and creditManager
        creditFacade.setContractToAdapter(adapter, targetContract); // F:[CC-15]
        creditManager.changeContractAllowance(adapter, targetContract); // F:[CC-15]

        // add contract to the list of allowed contracts
        allowedContractsSet.add(targetContract); // F:[CC-15]

        emit ContractAllowed(targetContract, adapter); // F:[CC-15]
    }

    /// @dev Forbids contract to use with credit manager
    /// Technically it meansh, that it sets address(0) in mappings:
    /// contractToAdapter[targetContract] = address(0)
    /// adapterToContract[existingAdapter] = address(0)
    /// @param targetContract Address of contract to be forbidden
    function forbidContract(address targetContract)
        external
        override
        configuratorOnly // F:[CC-2]
    {
        // Checks that targetContract is not address(0)
        if (targetContract == address(0)) revert ZeroAddressException(); // F:[CC-12]

        // Checks that targetContract has connected adapter
        address adapter = creditFacade.contractToAdapter(targetContract);
        if (adapter == address(0)) revert ContractNotInAllowedList(); // F:[CC-16]

        // Sets this map to address(0) which means that adapter / targerContract doesnt exist
        creditManager.changeContractAllowance(adapter, address(0)); // F:[CC-17]
        creditFacade.setContractToAdapter(address(0), targetContract); // F:[CC-17]

        // remove contract from list of allowed contracts
        allowedContractsSet.remove(targetContract); // F:[CC-17]

        emit ContractForbidden(targetContract); // F:[CC-17]
    }

    //
    // CREDIT MANAGER MGMT
    //

    /// @dev Sets limits for borrowed amount for creditManager
    /// @param _minBorrowedAmount Minimum allowed borrowed amount for creditManager
    /// @param _maxBorrowedAmount Maximum allowed borrowed amount for creditManager
    function setLimits(uint256 _minBorrowedAmount, uint256 _maxBorrowedAmount)
        external
        configuratorOnly // F:[CC-2]
    {
        _setParams(
            _minBorrowedAmount,
            _maxBorrowedAmount,
            creditManager.feeInterest(),
            creditManager.feeLiquidation(),
            creditManager.liquidationDiscount(),
            creditManager.chiThreshold(),
            creditManager.hfCheckInterval()
        ); // F:[CC-18]

        emit LimitsUpdated(_minBorrowedAmount, _maxBorrowedAmount); // F:[CC-18]
    }

    /// @dev Sets fastCheck parameters for creditManager
    /// It calls _setParams which makes additional coverage check
    /// @param _chiThreshold Chi threshold
    /// @param _hfCheckInterval Count steps between full check
    function setFastCheckParameters(
        uint256 _chiThreshold,
        uint256 _hfCheckInterval
    )
        external
        configuratorOnly // F:[CC-2]
    {
        // _chiThreshold should be always less or equal PERCENTAGE_FACTOR
        if (_chiThreshold > PERCENTAGE_FACTOR)
            revert ChiThresholdMoreOneException(); // F:[CC-19]

        _setParams(
            creditManager.minBorrowedAmount(),
            creditManager.maxBorrowedAmount(),
            creditManager.feeInterest(),
            creditManager.feeLiquidation(),
            creditManager.liquidationDiscount(),
            _chiThreshold,
            _hfCheckInterval
        ); // F:[CC-20]

        emit FastCheckParametersUpdated(_chiThreshold, _hfCheckInterval); // F:[CC-20]
    }

    /// @dev Sets fees for creditManager
    /// @param _feeInterest Percent which protocol charges additionally for interest rate
    /// @param _feeLiquidation Cut for totalValue which should be paid by Liquidator to the pool
    /// @param _liquidationPremium Discount for totalValue which becomes premium for liquidator
    function setFees(
        uint256 _feeInterest,
        uint256 _feeLiquidation,
        uint256 _liquidationPremium
    )
        external
        configuratorOnly // F:[CC-2]
    {
        // Checks that feeInterest and (liquidationPremium + feeLiquidation) in range [0..10000]
        if (
            _feeInterest >= PERCENTAGE_FACTOR ||
            (_liquidationPremium + _feeLiquidation) >= PERCENTAGE_FACTOR
        ) revert IncorrectFeesException(); // FT:[CC-22]

        _setParams(
            creditManager.minBorrowedAmount(),
            creditManager.maxBorrowedAmount(),
            _feeInterest,
            _feeLiquidation,
            PERCENTAGE_FACTOR - _liquidationPremium,
            creditManager.chiThreshold(),
            creditManager.hfCheckInterval()
        ); // FT:[CC-24,25]

        emit FeesUpdated(_feeInterest, _feeLiquidation, _liquidationPremium); // FT:[CC-25]
    }

    /// @dev This internal function is check the need of additional sanity checks
    /// Despite on changes, these checks could be:
    /// - fastCheckParameterCoverage = maximum collateral drop could not be less than feeLiquidation
    /// - updateLiquidationThreshold = Liquidation threshold for underlying token depends on fees, so
    ///   it additionally updated all LT for other tokens if they > than new liquidation threshold
    function _setParams(
        uint256 _minBorrowedAmount,
        uint256 _maxBorrowedAmount,
        uint256 _feeInterest,
        uint256 _feeLiquidation,
        uint256 _liquidationDiscount,
        uint256 _chiThreshold,
        uint256 _hfCheckInterval
    ) internal {
        uint256 newLTUnderlying = _liquidationDiscount - _feeLiquidation; // FT:[CC-23]

        // Computes new liquidationThreshold and update it for undelyingToken if needed
        if (
            newLTUnderlying != creditManager.liquidationThresholds(underlying)
        ) {
            _updateLiquidationThreshold(newLTUnderlying); // F:[CC-24]
        }

        uint256 currentChiThreshold = creditManager.chiThreshold();
        uint256 currentHfCheckInterval = creditManager.hfCheckInterval();
        uint256 currentFeeLiquidation = creditManager.feeLiquidation();

        // Checks that fastCheckParameters were changed, if so it runs additional coverage check
        if (
            _chiThreshold != currentChiThreshold ||
            _hfCheckInterval != currentHfCheckInterval ||
            _feeLiquidation != currentFeeLiquidation
        ) {
            _checkFastCheckParamsCoverage(
                _chiThreshold,
                _hfCheckInterval,
                _feeLiquidation
            ); // F:[CC-21]
        }

        // updates params in creditManager
        creditManager.setParams(
            _minBorrowedAmount,
            _maxBorrowedAmount,
            _feeInterest,
            _feeLiquidation,
            _liquidationDiscount,
            _chiThreshold,
            _hfCheckInterval
        );
    }

    /// @dev Updates Liquidation threshold for underlying asset
    ///
    function _updateLiquidationThreshold(uint256 ltUnderlying) internal {
        creditManager.setLiquidationThreshold(underlying, ltUnderlying); // F:[CC-24]

        uint256 len = creditManager.allowedTokensCount();
        for (uint256 i = 1; i < len; ) {
            address token = creditManager.allowedTokens(i);
            if (creditManager.liquidationThresholds(token) > ltUnderlying) {
                creditManager.setLiquidationThreshold(token, ltUnderlying); // F:[CC-24]
            }

            unchecked {
                i++;
            }
        }
    }

    /// @dev It checks that 1 - chi ** hfCheckInterval < feeLiquidation
    function _checkFastCheckParamsCoverage(
        uint256 chiThreshold,
        uint256 hfCheckInterval,
        uint256 feeLiquidation
    ) internal pure {
        // computes maximum possible collateral drop between two health factor checks
        uint256 maxPossibleDrop = PERCENTAGE_FACTOR -
            calcMaxPossibleDrop(chiThreshold, hfCheckInterval); // F:[CC-21]

        if (maxPossibleDrop > feeLiquidation)
            revert FastCheckNotCoverCollateralDropException(); // F:[CC-21, 23]
    }

    // @dev it computes percentage ** times
    // @param percentage Percentage in PERCENTAGE FACTOR format
    function calcMaxPossibleDrop(uint256 percentage, uint256 times)
        public
        pure
        returns (uint256 value)
    {
        // Case for times = type(uint256).max
        if (percentage == PERCENTAGE_FACTOR) {
            return PERCENTAGE_FACTOR;
        } // F:[CC-26]

        value = percentage * PERCENTAGE_FACTOR; // F:[CC-26]

        if (times > 1) {
            for (uint256 i = 0; i < times - 1; i++) {
                value = (value * percentage) / PERCENTAGE_FACTOR; // F:[CC-26]
            }
        }
        value = value / PERCENTAGE_FACTOR; // F:[CC-26]
    }

    //
    // CONTRACT UPGRADES
    //

    // It upgrades priceOracle which addess is taken from addressProvider
    function upgradePriceOracle()
        external
        configuratorOnly // F:[CC-2]
    {
        address priceOracle = addressProvider.getPriceOracle();
        creditManager.upgradeContracts(
            creditManager.creditFacade(),
            priceOracle
        ); // F:[CC-27]
        emit PriceOracleUpgraded(priceOracle); // F:[CC-27]
    }

    // It upgrades creditFacade
    function upgradeCreditFacade(address _creditFacade)
        external
        configuratorOnly // F:[CC-2]
    {
        creditManager.upgradeContracts(
            _creditFacade,
            address(creditManager.priceOracle())
        ); // F:[CC-28]
        emit CreditFacadeUpgraded(_creditFacade); // F:[CC-28]
    }

    function upgradeConfigurator(address _creditConfigurator)
        external
        configuratorOnly // F:[CC-2]
    {
        creditManager.setConfigurator(_creditConfigurator);
    }

    //
    function setDegenMode(bool _mode)
        external
        configuratorOnly // TODO: cover with test
    {
        creditFacade.setDegenMode(_mode);
    }

    function setIncreaseDebtForbidden(bool _mode) external configuratorOnly {
        creditFacade.setIncreaseDebtForbidden(_mode);
    }

    //
    // GETTERS
    //

    /// @dev Returns quantity of contracts in allowed list
    function allowedContractsCount() external view override returns (uint256) {
        return allowedContractsSet.length(); // T:[CF-9]
    }

    /// @dev Returns allowed contract by index
    function allowedContracts(uint256 i)
        external
        view
        override
        returns (address)
    {
        return allowedContractsSet.at(i); // T:[CF-9]
    }
}
