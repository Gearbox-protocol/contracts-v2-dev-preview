import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

interface IYearnPriceFeedEvents {
    event NewLimiterParams(uint256 lowerBound, uint256 upperBound);
}

interface IYearnPriceFeedExceptions {
    error PricePerShareOutOfRangeExpcetion();
    error IncorrectLimitsException();
}

/// @title Yearn Chainlink pricefeed adapter
interface IYearnPriceFeed is
    AggregatorV3Interface,
    IYearnPriceFeedEvents,
    IYearnPriceFeedExceptions
{

}
