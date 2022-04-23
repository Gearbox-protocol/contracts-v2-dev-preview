// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {ICurvePool} from "../../integrations/curve/ICurvePool.sol";

// EXCEPTIONS
import {ZeroAddressException, NotImplementedException} from "../../interfaces/IErrors.sol";

/// @title CurveLP pricefeed for 2 assets
contract CurveLP2PriceFeed is AggregatorV3Interface {
    ICurvePool public immutable curvePool;

    AggregatorV3Interface public immutable priceFeed1;
    AggregatorV3Interface public immutable priceFeed2;

    // PriceFeed options
    uint8 public constant override decimals = 8;
    uint256 public constant override version = 1;
    string public override description;

    constructor(
        address _curvePool,
        address _priceFeed1,
        address _priceFeed2,
        string memory _description
    ) {
        if (
            _curvePool == address(0) ||
            _priceFeed1 == address(0) ||
            _priceFeed2 == address(0)
        ) revert ZeroAddressException();

        curvePool = ICurvePool(_curvePool); // F:[OCLP-1]
        priceFeed1 = AggregatorV3Interface(_priceFeed1); // F:[OCLP-1]
        priceFeed2 = AggregatorV3Interface(_priceFeed2); // F:[OCLP-1]
        description = _description; // F:[OCLP-1]
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
        // Function can get real value, cause there is no way to get historic value for get_virtual_price()
        revert NotImplementedException(); // F:[OCLP-3]
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed1
            .latestRoundData(); // F:[OCLP-4]

        (
            uint80 roundId2,
            int256 answer2,
            uint256 startedAt2,
            uint256 updatedAt2,
            uint80 answeredInRound2
        ) = priceFeed2.latestRoundData(); // F:[OCLP-4]

        if (answer2 < answer) {
            roundId = roundId2;
            answer = answer2;
            startedAt = startedAt2;
            updatedAt = updatedAt2;
            answeredInRound = answeredInRound2;
        } // F:[OCLP-4]

        answer = (answer * int256(curvePool.get_virtual_price())) / 10**18; // F:[OCLP-4]
    }
}
