// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

/// @dev Struct which represents configuration for token from allowed token list
struct AllowedToken {
    address token; // Address of token
    uint256 liquidationThreshold; // LT for token in range 0..10,000 which represents 0-100%
}

/// @dev struct which represents CreditManager V2 configuration
struct CreditManagerOpts {
    uint256 minBorrowedAmount; // minimal amount for credit account
    uint256 maxBorrowedAmount; // maximum amount for credit account
    AllowedToken[] allowedTokens; // allowed tokens list
    address degenNFT; // Address of Degen NFT, address(0) for skipping degen mode
}

/// @dev CreditConfigurator Events
interface ICreditConfiguratorEvents {
    // Emits each time token is allowed or liquidtion threshold changed
    event TokenLiquidationThresholdUpdated(
        address indexed token,
        uint256 liquidityThreshold
    );

    // Emits each time token is allowed or liquidtion threshold changed
    event TokenAllowed(address indexed token);

    // Emits each time token is allowed or liquidtion threshold changed
    event TokenForbidden(address indexed token);

    // Emits each time contract is allowed or adapter changed
    event ContractAllowed(address indexed protocol, address indexed adapter);

    // Emits each time contract is forbidden
    event ContractForbidden(address indexed protocol);

    event LimitsUpdated(uint256 minBorrowedAmount, uint256 maxBorrowedAmount);

    // Emits each time when fast check parameters are updated
    event FastCheckParametersUpdated(
        uint256 chiThreshold,
        uint256 fastCheckDelay
    );

    event FeesUpdated(
        uint256 feeInterest,
        uint256 feeLiquidation,
        uint256 liquidationPremium
    );

    event PriceOracleUpgraded(address indexed newPriceOracle);

    event CreditFacadeUpgraded(address indexed newCreditFacade);

    event CreditConfiguratorUpgraded(address indexed newCreditConfigurator);
}

/// @dev CreditConfigurator Exceptions
interface ICreditConfiguratorExceptions {
    /// @dev throws if token has no balanceOf(address) method, or this method reverts
    error IncorrectTokenContractException();

    /// @dev throws if token has no priceFeed in PriceOracle
    error IncorrectPriceFeedException();

    /// @dev throws if configurator tries to set Liquidation Threshold directly
    error SetLTForUnderlyingException();

    /// @dev throws if liquidationThreshold is out of range (0; LT for underlying token]
    error IncorrectLiquidationThresholdException();

    /// @dev throws if feeInterest or (liquidationPremium + feeLiquidation) is out of range [0; 10.000] which means [0%; 100%]
    error IncorrectFeesException();

    error FastCheckNotCoverCollateralDropException();

    error CreditManagerOrFacadeUsedAsAllowContractsException();

    error AdapterUsedTwiceException();

    error AdapterHasIncorrectCreditManagerException();

    error ContractNotInAllowedList();

    error ChiThresholdMoreOneException();
}

interface ICreditConfigurator is
    ICreditConfiguratorEvents,
    ICreditConfiguratorExceptions
{
    //
    // STATE-CHANGING FUNCTIONS
    //

    /// @dev Adds token to the list of allowed tokens
    /// @param token Address of allowed token
    function addTokenToAllowedList(address token) external;

    /// @dev Adds token to the list of allowed tokens
    /// @param token Address of allowed token
    /// @param liquidationThreshold The constant showing the maximum allowable ratio of Loan-To-Value for the i-th asset.
    function setLiquidationThreshold(
        address token,
        uint256 liquidationThreshold
    ) external;

    /// @dev Adds contract to the list of allowed contracts
    /// @param targetContract Address of contract to be allowed
    /// @param adapter Adapter contract address
    function allowContract(address targetContract, address adapter) external;

    /// @dev Forbids contract and removes it from the list of allowed contracts
    /// @param targetContract Address of allowed contract
    function forbidContract(address targetContract) external;

    function allowedContractsCount() external view returns (uint256);

    /// @dev Returns allowed contract by index
    function allowedContracts(uint256 i) external view returns (address);
}
