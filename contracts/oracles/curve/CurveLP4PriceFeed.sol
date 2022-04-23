// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;

import {ICurvePool} from "../../integrations/curve/ICurvePool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

// EXCEPTIONS
import {ZeroAddressException, NotImplementedException} from "../../interfaces/IErrors.sol";

/// @title CurveLP pricefeed for 4 assets
contract CurveLP4PriceFeed is AggregatorV3Interface {
    ICurvePool public immutable curvePool;

    AggregatorV3Interface public immutable priceFeed1;
    AggregatorV3Interface public immutable priceFeed2;
    AggregatorV3Interface public immutable priceFeed3;
    AggregatorV3Interface public immutable priceFeed4;

    // PriceFeed options
    uint8 public constant override decimals = 8;
    uint256 public constant override version = 1;
    string public override description;

    constructor(
        address _curvePool,
        address _priceFeed1,
        address _priceFeed2,
        address _priceFeed3,
        address _priceFeed4,
        string memory _description
    ) {
        if (
            _curvePool == address(0) ||
            _priceFeed1 == address(0) ||
            _priceFeed2 == address(0) ||
            _priceFeed3 == address(0) ||
            _priceFeed4 == address(0)
        ) revert ZeroAddressException();

        curvePool = ICurvePool(_curvePool); // F:[OCLP-1]
        priceFeed1 = AggregatorV3Interface(_priceFeed1); // F:[OCLP-1]
        priceFeed2 = AggregatorV3Interface(_priceFeed2); // F:[OCLP-1]
        priceFeed3 = AggregatorV3Interface(_priceFeed3); // F:[OCLP-1]
        priceFeed4 = AggregatorV3Interface(_priceFeed4); // F:[OCLP-1]
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
        uint80 roundIdA;
        int256 answerA;
        uint256 startedAtA;
        uint256 updatedAtA;
        uint80 answeredInRoundA;

        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed1
            .latestRoundData(); // F:[OCLP-6]

        (
            roundIdA,
            answerA,
            startedAtA,
            updatedAtA,
            answeredInRoundA
        ) = priceFeed2.latestRoundData(); // F:[OCLP-6]

        if (answerA < answer) {
            roundId = roundIdA;
            answer = answerA;
            startedAt = startedAtA;
            updatedAt = updatedAtA;
            answeredInRound = answeredInRoundA;
        } // F:[OCLP-6]

        (
            roundIdA,
            answerA,
            startedAtA,
            updatedAtA,
            answeredInRoundA
        ) = priceFeed3.latestRoundData(); // F:[OCLP-6]

        if (answerA < answer) {
            roundId = roundIdA;
            answer = answerA;
            startedAt = startedAtA;
            updatedAt = updatedAtA;
            answeredInRound = answeredInRoundA;
        } // F:[OCLP-6]

        (
            roundIdA,
            answerA,
            startedAtA,
            updatedAtA,
            answeredInRoundA
        ) = priceFeed4.latestRoundData(); // F:[OCLP-6]

        if (answerA < answer) {
            roundId = roundIdA;
            answer = answerA;
            startedAt = startedAtA;
            updatedAt = updatedAtA;
            answeredInRound = answeredInRoundA;
        } // F:[OCLP-6]

        answer = (answer * int256(curvePool.get_virtual_price())) / 10**18; // F:[OCLP-6]
    }
}
