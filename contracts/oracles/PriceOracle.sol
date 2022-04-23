// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AddressProvider} from "../core/AddressProvider.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

// CONSTANTS
import {WAD} from "../libraries/WadRayMath.sol";

// EXCEPTIONS
import {ZeroAddressException} from "../interfaces/IErrors.sol";

//import "hardhat/console.sol";

struct PriceFeedConfig {
    address token;
    address priceFeed;
}

/// @title Price Oracle based on Chainlink's price feeds
/// @notice Works as router and provide cross rates using converting via USD
///
/// More: https://dev.gearbox.fi/developers/priceoracle
contract PriceOracle is ACLTrait, IPriceOracle {
    // token => priceFeed
    mapping(address => address) public override priceFeeds;

    // token => decimals multiplier
    mapping(address => uint256) public decimals;

    // Contract version
    uint256 public constant version = 2;

    constructor(address addressProvider, PriceFeedConfig[] memory defaults)
        ACLTrait(addressProvider)
    {
        uint256 len = defaults.length;
        for (uint256 i = 0; i < len; ) {
            _addPriceFeed(defaults[i].token, defaults[i].priceFeed); // F:[PO-1]

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Sets price feed if it doesn't exist. If price feed is already set, it changes nothing
    /// This logic is done to protect Gearbox from priceOracle attack
    /// when potential attacker can get access to price oracle, change them to fraud ones
    /// and then liquidate all funds
    /// @param token Address of token
    /// @param priceFeed Address of chainlink price feed token => Eth
    function addPriceFeed(address token, address priceFeed)
        external
        configuratorOnly
    {
        _addPriceFeed(token, priceFeed);
    }

    function _addPriceFeed(address token, address priceFeed) internal {
        if (token == address(0) || priceFeed == address(0))
            revert ZeroAddressException(); // F:[PO-2]

        uint256 tokenDecimals = ERC20(token).decimals();

        if (tokenDecimals > 18)
            revert TokenDecimalsGreater18ForbiddenException(); // F:[PO-2]

        if (AggregatorV3Interface(priceFeed).decimals() != 8)
            revert PriceFeedDecimalsNotEqual8Exception(); // F:[PO-2]

        priceFeeds[token] = priceFeed; // F:[PO-3]
        decimals[token] = 10**tokenDecimals; // F:[PO-3]

        emit NewPriceFeed(token, priceFeed); // F:[PO-3]
    }

    /// Converts one asset into USD (decimals = 8). Reverts if priceFeed doesn't exist
    /// @param amount Amount to convert
    /// @param token Token address converts from
    /// @return Amount converted to tokenTo asset
    function convertToUSD(uint256 amount, address token)
        public
        view
        override
        returns (uint256)
    {
        return (amount * _getPrice(token)) / decimals[token]; // F:[PO-4]
    }

    /// @dev Converts one asset into another using price feed rate. Reverts if price feed doesn't exist
    /// @param amount Amount to convert
    /// @param token Token address converts from
    /// @return Amount converted to tokenTo asset
    function convertFromUSD(uint256 amount, address token)
        public
        view
        override
        returns (uint256)
    {
        return (amount * decimals[token]) / _getPrice(token); // F:[PO-4]
    }

    /// @dev Converts one asset into another using price feed rate. Reverts if price feed doesn't exist
    /// @param amount Amount to convert
    /// @param tokenFrom Token address converts from
    /// @param tokenTo Token address - converts to
    /// @return Amount converted to tokenTo asset
    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) public view override returns (uint256) {
        return convertFromUSD(convertToUSD(amount, tokenFrom), tokenTo); // F:[PO-5]
    }

    /// @dev Converts one asset into another using price feed rate. Reverts if price feed doesn't exist
    /// @param amountFrom Amount to convert
    /// @param tokenFrom Token address converts from
    /// @param tokenTo Token address - converts to
    function fastCheck(
        uint256 amountFrom,
        address tokenFrom,
        uint256 amountTo,
        address tokenTo
    )
        external
        view
        override
        returns (uint256 collateralFrom, uint256 collateralTo)
    {
        collateralFrom = convertToUSD(amountFrom, tokenFrom); // F:[PO-6]
        collateralTo = convertToUSD(amountTo, tokenTo); // F:[PO-6]
    }

    /// @dev Returns rate to ETH in WAD format
    /// @param token Token converts from
    function _getPrice(address token) internal view returns (uint256) {
        if (priceFeeds[token] == address(0))
            revert PriceOracleNotExistsException();

        (
            ,
            //uint80 roundID,
            int256 price, //uint startedAt, , //uint80 answeredInRound
            ,
            ,

        ) = AggregatorV3Interface(priceFeeds[token]).latestRoundData();

        if (price == 0) revert ZeroPriceException(); // TODO: cover with test

        return uint256(price);
    }
}
