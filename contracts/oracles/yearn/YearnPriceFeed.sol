// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import {IYearnPriceFeed} from "../../integrations/yearn/IYearnPriceFeed.sol";

import {IYVault} from "../../integrations/yearn/IYVault.sol";
import {ACLTrait} from "../../core/ACLTrait.sol";
import {PercentageMath} from "../../libraries/PercentageMath.sol";

// EXCEPTIONS
import {ZeroAddressException, NotImplementedException} from "../../interfaces/IErrors.sol";

/// @title Yearn Chainlink pricefeed adapter
contract YearnPriceFeed is IYearnPriceFeed, ACLTrait {
    AggregatorV3Interface public immutable priceFeed;
    IYVault public immutable yVault;
    uint256 public immutable decimalsDivider;
    uint256 public lowerBound;
    uint256 public upperBound;

    constructor(
        address addressProvider,
        address _yVault,
        address _priceFeed,
        uint256 _lowerBound,
        uint256 _upperBound
    ) ACLTrait(addressProvider) {
        if (_yVault == address(0) || _priceFeed == address(0))
            revert ZeroAddressException();

        yVault = IYVault(_yVault);
        priceFeed = AggregatorV3Interface(_priceFeed);
        decimalsDivider = 10**yVault.decimals();
        _setLimiter(_lowerBound, _upperBound);
    }

    function decimals() external view override returns (uint8) {
        return priceFeed.decimals();
    }

    function description() external view override returns (string memory) {
        return priceFeed.description();
    }

    function version() external view override returns (uint256) {
        return priceFeed.version();
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (
            uint80, // roundId,
            int256, // answer,
            uint256, // startedAt,
            uint256, // updatedAt,
            uint80 // answeredInRound
        )
    {
        revert NotImplementedException();
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed
            .latestRoundData();

        uint256 pricePerShare = yVault.pricePerShare();

        if (pricePerShare < lowerBound || pricePerShare > upperBound)
            revert PricePerShareOutOfRangeExpcetion();

        answer = int256((pricePerShare * uint256(answer)) / decimalsDivider);
    }

    function setLimiter(uint256 _lowerBound, uint256 _upperBound)
        external
        configuratorOnly
    {
        _setLimiter(_lowerBound, _upperBound);
    }

    function _setLimiter(uint256 _lowerBound, uint256 _upperBound) internal {
        if (_lowerBound == 0 || _upperBound < _lowerBound)
            revert PricePerShareOutOfRangeExpcetion();
        lowerBound = _lowerBound;
        upperBound = _upperBound;
        emit NewLimiterParams(lowerBound, upperBound);
    }
}
