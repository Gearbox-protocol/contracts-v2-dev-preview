// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import { AdapterType} from "../interfaces/adapters/IAdapter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {WAD} from "../libraries/WadRayMath.sol";
import {ISwapRouter} from "../integrations/uniswap/IUniswapV3.sol";
import {IUniswapV2Router02} from "../integrations/uniswap/IUniswapV2Router02.sol";
import {BytesLib} from "../integrations/uniswap/BytesLib.sol";
import {ICurvePool} from "../integrations/curve/ICurvePool.sol";
import {EXACT_INPUT, EXACT_OUTPUT} from "../libraries/Constants.sol";
import {Errors} from "../libraries/Errors.sol";
import {IQuoter} from "../integrations/uniswap/IQuoter.sol";
import {AddressProvider} from "../core/AddressProvider.sol";
import {ContractsRegister} from "../core/ContractsRegister.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {PriceOracle} from "../oracles/PriceOracle.sol";

contract PathFinder {
    using BytesLib for bytes;
    AddressProvider public immutable addressProvider;
    ContractsRegister public immutable contractsRegister;
    PriceOracle public immutable priceOracle;
    address public immutable wethToken;

    // Mainnet
    address public constant ethToUsdPriceFeed =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Kovan
    //    address public constant ethToUsdPriceFeed =
    //        0x9326BFA02ADD2366b30bacB125260Af641031331;

    // Contract version
    uint256 public constant version = 1;

    struct TradePath {
        address[] path;
        uint256 rate;
        uint256 expectedAmount;
    }

    /// @dev Allows provide data for registered credit managers only to eliminated usage for non-gearbox contracts
    modifier registeredCreditManagerOnly(address creditManager) {
        // Could be optimised by adding internal list of creditManagers
        require(
            contractsRegister.isCreditManager(creditManager),
            Errors.REGISTERED_CREDIT_ACCOUNT_MANAGERS_ONLY
        ); // T:[WG-3]

        _;
    }

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(_addressProvider);
        contractsRegister = ContractsRegister(
            addressProvider.getContractsRegister()
        );

        priceOracle = PriceOracle(addressProvider.getPriceOracle());
        wethToken = addressProvider.getWethToken();
    }

    function bestUniPath(
        AdapterType swapInterface,
        address router,
        uint256 swapType,
        address from,
        address to,
        uint256 amount,
        address[] memory tokens
    ) public returns (TradePath memory) {
        if (amount == 0) {
            return
                TradePath({path: new address[](3), rate: 0, expectedAmount: 0});
        }

        // Checking path[2]:  [from,to]
        address[] memory path = new address[](2);

        path[0] = from;
        path[1] = to;

        (uint256 bestAmount, bool best) = _getAmountsUni(
            swapInterface,
            router,
            swapType,
            path,
            amount,
            swapType == EXACT_INPUT ? 0 : type(uint256).max
        );

        address[] memory bestPath;
        uint256 expectedAmount;

        if (best) {
            bestPath = path;
        }

        // Checking path[3]: [from, <connector>, to]
        for (uint256 i = 0; i < tokens.length; i++) {
            path = new address[](3);
            path[0] = from;
            path[2] = to;

            if (tokens[i] != from && tokens[i] != to) {
                path[1] = tokens[i];
                (expectedAmount, best) = _getAmountsUni(
                    swapInterface,
                    router,
                    swapType,
                    path,
                    amount,
                    bestAmount
                );
                if (best) {
                    bestAmount = expectedAmount;
                    bestPath = path;
                }
            }
        }

        uint256 bestRate = 0;

        if (bestAmount == type(uint256).max) {
            bestAmount = 0;
        }

        if (bestAmount != 0 && amount != 0) {
            bestRate = swapType == EXACT_INPUT
                ? (WAD * amount) / bestAmount
                : (WAD * bestAmount) / amount;
        }

        return
            TradePath({
                rate: bestRate,
                path: bestPath,
                expectedAmount: bestAmount
            });
    }

    function _getAmountsUni(
        AdapterType swapInterface,
        address router,
        uint256 swapType,
        address[] memory path,
        uint256 amount,
        uint256 bestAmount
    ) internal returns (uint256, bool) {
        return
            swapInterface == AdapterType.UNISWAP_V2
                ? _getAmountsV2(
                    IUniswapV2Router02(router),
                    swapType,
                    path,
                    amount,
                    bestAmount
                )
                : _getAmountsV3(
                    IQuoter(router),
                    swapType,
                    path,
                    amount,
                    bestAmount
                );
    }

    function _getAmountsV2(
        IUniswapV2Router02 router,
        uint256 swapType,
        address[] memory path,
        uint256 amount,
        uint256 bestAmount
    ) internal view returns (uint256, bool) {
        uint256 expectedAmount;

        if (swapType == EXACT_INPUT) {
            try router.getAmountsOut(amount, path) returns (
                uint256[] memory amountsOut
            ) {
                expectedAmount = amountsOut[path.length - 1];
            } catch {
                return (bestAmount, false);
            }
        } else if (swapType == EXACT_OUTPUT) {
            try router.getAmountsIn(amount, path) returns (
                uint256[] memory amountsIn
            ) {
                expectedAmount = amountsIn[0];
            } catch {
                return (bestAmount, false);
            }
        } else {
            revert("Unknown swap type");
        }

        if (
            (swapType == EXACT_INPUT && expectedAmount > bestAmount) ||
            (swapType == EXACT_OUTPUT && expectedAmount < bestAmount)
        ) {
            return (expectedAmount, true);
        }

        return (bestAmount, false);
    }

    function _getAmountsV3(
        IQuoter quoter,
        uint256 swapType,
        address[] memory path,
        uint256 amount,
        uint256 bestAmount
    ) internal returns (uint256, bool) {
        uint256 expectedAmount;

        if (swapType == EXACT_INPUT) {
            try
                quoter.quoteExactInput(
                    convertPathToPathV3(path, swapType),
                    amount
                )
            returns (uint256 amountOut) {
                expectedAmount = amountOut;
            } catch {
                return (bestAmount, false);
            }
        } else if (swapType == EXACT_OUTPUT) {
            try
                quoter.quoteExactOutput(
                    convertPathToPathV3(path, swapType),
                    amount
                )
            returns (uint256 amountIn) {
                expectedAmount = amountIn;
            } catch {
                return (bestAmount, false);
            }
        } else {
            revert("Unknown swap type");
        }

        if (
            (swapType == EXACT_INPUT && expectedAmount > bestAmount) ||
            (swapType == EXACT_OUTPUT && expectedAmount < bestAmount)
        ) {
            return (expectedAmount, true);
        }

        return (bestAmount, false);
    }

    function convertPathToPathV3(address[] memory path, uint256 swapType)
        public
        pure
        returns (bytes memory result)
    {
        uint24 fee = 3000;

        if (swapType == EXACT_INPUT) {
            for (uint256 i = 0; i < path.length - 1; i++) {
                result = result.concat(abi.encodePacked(path[i], fee));
            }
            result = result.concat(abi.encodePacked(path[path.length - 1]));
        } else {
            for (uint256 i = path.length - 1; i > 0; i--) {
                result = result.concat(abi.encodePacked(path[i], fee));
            }
            result = result.concat(abi.encodePacked(path[0]));
        }
    }

    function getClosurePaths(
        address router,
        address _creditManager,
        address borrower,
        address[] memory connectorTokens
    )
        external
        registeredCreditManagerOnly(_creditManager)
        returns (TradePath[] memory result)
    {
//        ICreditFilter creditFilter = ICreditFilter(
//            ICreditManager(_creditManager).creditFilter()
//        );
//        result = new TradePath[](creditFilter.allowedTokensCount());
//
//        address creditAccount = ICreditManager(_creditManager)
//        .getCreditAccountOrRevert(borrower);
//        address underlying = creditFilter.underlying();
//
//        uint256 count = creditFilter.allowedTokensCount();
//        for (uint256 i = 0; i <count ; ) {
//            (address token, uint256 balance ) = creditFilter
//            .getCreditAccountTokenById(creditAccount, i);
//
//            if (i == 0) {
//                result[0] = TradePath({
//                    path: new address[](3),
//                    rate: WAD,
//                    expectedAmount: balance
//                });
//            } else {
//                result[i] = bestUniPath(
//                    AdapterType.UNISWAP_V2,
//                    router,
//                    EXACT_INPUT,
//                    token,
//                    underlying,
//                    balance,
//                    connectorTokens
//                );
//            }
//
//            unchecked{ i++; }
//        }

    }

    function getPrices(address[] calldata tokens)
        external
        view
        returns (uint256[] memory prices)
    {
        (
            ,
            //uint80 roundID,
            int256 ethPrice, //uint startedAt, //uint timeStamp, //uint80 answeredInRound
            ,
            ,

        ) = AggregatorV3Interface(ethToUsdPriceFeed).latestRoundData();
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 decimals = ERC20(tokens[i]).decimals();
            prices[i] =
                (priceOracle.convert(10**decimals, tokens[i], wethToken) *
                    (uint256(ethPrice))) /
                (WAD);
        }
    }
}
