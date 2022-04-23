// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import {PercentageMath, PERCENTAGE_FACTOR} from "../libraries/PercentageMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreditAccount} from "../interfaces/ICreditAccount.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {CreditManager} from "../credit/CreditManager.sol";
import {IPoolService} from "../interfaces/IPoolService.sol";
import {ICreditFacade} from "../interfaces/ICreditFacade.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {AddressProvider} from "./AddressProvider.sol";
import {ContractsRegister} from "./ContractsRegister.sol";

import {CreditAccountData, CreditManagerData, PoolData, TokenInfo, TokenBalance, ContractAdapter} from "../libraries/Types.sol";
import {Errors} from "../libraries/Errors.sol";

/// @title Data compressor
/// @notice Collects data from different contracts to send it to dApp
/// Do not use for data from data compressor for state-changing functions
contract DataCompressor {
    using PercentageMath for uint256;

    AddressProvider public immutable addressProvider;
    ContractsRegister public immutable contractsRegister;
    address public immutable WETHToken;

    // Contract version
    uint256 public constant version = 2;

    /// @dev Allows provide data for registered pools only to eliminated usage for non-gearbox contracts
    modifier registeredPoolOnly(address pool) {
        // Could be optimised by adding internal list of pools
        require(contractsRegister.isPool(pool), Errors.REGISTERED_POOLS_ONLY); // T:[WG-1]

        _;
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
        require(
            _addressProvider != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        addressProvider = AddressProvider(_addressProvider);
        contractsRegister = ContractsRegister(
            addressProvider.getContractsRegister()
        );
        WETHToken = addressProvider.getWethToken();
    }

    /// @dev Returns CreditAccountData for all opened account for particluar borrower
    /// @param borrower Borrower address
    function getCreditAccountList(address borrower)
        external
        view
        returns (CreditAccountData[] memory)
    {
        // Counts how much opened account a borrower has
        uint256 count;
        for (
            uint256 i = 0;
            i < contractsRegister.getCreditManagersCount();
            i++
        ) {
            address creditManager = contractsRegister.creditManagers(i);
            if (hasOpenedCreditAccount(creditManager, borrower)) {
                count++;
            }
        }

        CreditAccountData[] memory result = new CreditAccountData[](count);

        // Get data & fill the array
        count = 0;
        for (
            uint256 i = 0;
            i < contractsRegister.getCreditManagersCount();
            i++
        ) {
            address creditManager = contractsRegister.creditManagers(i);
            if (hasOpenedCreditAccount(creditManager, borrower)) {
                result[count] = getCreditAccountData(creditManager, borrower);
                count++;
            }
        }
        return result;
    }

    function hasOpenedCreditAccount(address _creditManager, address borrower)
        public
        view
        registeredCreditManagerOnly(_creditManager)
        returns (bool)
    {
        return _hasOpenedCreditAccount(_creditManager, borrower);
    }

    /// @dev Returns CreditAccountData for particular account for creditManager and borrower
    /// @param _creditManager Credit manager address
    /// @param borrower Borrower address
    function getCreditAccountData(address _creditManager, address borrower)
        public
        view
        returns (CreditAccountData memory)
    {
        (
            ICreditManager creditManager,
            ICreditFacade creditFacade
        ) = getCreditContracts(_creditManager);

        address creditAccount = creditManager.getCreditAccountOrRevert(
            borrower
        );

        CreditAccountData memory result;

        result.borrower = borrower;
        result.creditManager = _creditManager;
        result.addr = creditAccount;

        result.underlying = creditManager.underlying();
        //        (result.totalValue, ) = creditManager.calcTotalValue(
        //            creditAccount,
        //            false
        //        );

        //        result.healthFactor = creditManager.calcCreditAccountHealthFactor(
        //            creditAccount
        //        );

        address pool = address(creditManager.poolService());
        result.borrowRate = IPoolService(pool).borrowAPY_RAY();

        uint256 allowedTokenCount = creditManager.allowedTokensCount();

        //        result.balances = new TokenBalance[](allowedTokenCount);
        //        for (uint256 i = 0; i < allowedTokenCount; i++) {
        //            TokenBalance memory balance;
        //            balance.token = creditManager.
        //            (balance.token, balance.balance) = creditFacade
        //            .getCreditAccountTokenById(creditAccount, i);
        //            balance.isAllowed = creditFacade.isTokenAllowed(balance.token);
        //            result.balances[i] = balance;
        //        }

        (
            result.borrowedAmount,
            result.borrowedAmountPlusInterest
        ) = creditManager.calcCreditAccountAccruedInterest(creditAccount);

        result.cumulativeIndexAtOpen = ICreditAccount(creditAccount)
        .cumulativeIndexAtOpen();

        result.since = ICreditAccount(creditAccount).since();
        //        result.repayAmount = ICreditManager(creditManager).calcRepayAmount(
        //            borrower,
        //            false
        //        );
        //        result.liquidationAmount = ICreditManager(creditManager)
        //        .calcRepayAmount(borrower, true);

        //        (, , uint256 remainingFunds, , ) = ICreditManager(creditManager)
        //        ._calcClosePayments(creditAccount, result.totalValue, false);
        //
        //        result.canBeClosed = remainingFunds > 0;
        result.version = uint8(ICreditManager(creditManager).version());

        return result;
    }

    /// @dev Returns all credit managers data + hasOpendAccount flag for bborrower
    /// @param borrower Borrower address
    function getCreditManagersList(address borrower)
        external
        view
        returns (CreditManagerData[] memory)
    {
        uint256 creditManagersCount = contractsRegister
        .getCreditManagersCount();

        CreditManagerData[] memory result = new CreditManagerData[](
            creditManagersCount
        );

        uint256 j = 0;
        for (uint256 i = 0; i < creditManagersCount; i++) {
            address creditManager = contractsRegister.creditManagers(i);
            if (CreditManager(creditManager).version() == 1) {
                continue;
            }

            result[j] = getCreditManagerData(creditManager, borrower);
            j++;
        }

        return result;
    }

    /// @dev Returns CreditManagerData for particular _creditManager and
    /// set flg hasOpenedCreditAccount for provided borrower
    /// @param _creditManager CreditManager address
    /// @param borrower Borrower address
    function getCreditManagerData(address _creditManager, address borrower)
        public
        view
        returns (CreditManagerData memory)
    {
        (
            ICreditManager creditManager,
            ICreditFacade creditFacade
        ) = getCreditContracts(_creditManager);

        CreditManagerData memory result;

        result.addr = _creditManager;
        result.hasAccount = hasOpenedCreditAccount(_creditManager, borrower);

        result.underlying = creditManager.underlying();
        result.isWETH = result.underlying == WETHToken;

        IPoolService pool = IPoolService(creditManager.poolService());
        result.canBorrow = pool.creditManagersCanBorrow(_creditManager);
        result.borrowRate = pool.borrowAPY_RAY();
        result.availableLiquidity = pool.availableLiquidity();
        //        result.minAmount = creditManager.minAmount();
        //        result.maxAmount = creditManager.maxAmount();
        //        result.maxLeverageFactor = creditManager.maxLeverageFactor();

        uint256 allowedTokenCount = creditManager.allowedTokensCount();

        result.allowedTokens = new address[](allowedTokenCount);
        for (uint256 i = 0; i < allowedTokenCount; i++) {
            result.allowedTokens[i] = creditManager.allowedTokens(i);
        }

        //        uint256 allowedContractsCount = creditFacade.allowedContractsCount();
        //
        //        result.adapters = new ContractAdapter[](allowedContractsCount);
        //        for (uint256 i = 0; i < allowedContractsCount; i++) {
        //            ContractAdapter memory adapter;
        //            adapter.allowedContract = creditFacade.allowedContracts(i);
        //            adapter.adapter = creditFacade.contractToAdapter(
        //                adapter.allowedContract
        //            );
        //            result.adapters[i] = adapter;
        //        }

        result.version = uint8(creditManager.version());

        return result;
    }

    /// @dev Returns PoolData for particulr pool
    /// @param _pool Pool address
    function getPoolData(address _pool)
        public
        view
        registeredPoolOnly(_pool)
        returns (PoolData memory)
    {
        PoolData memory result;
        IPoolService pool = IPoolService(_pool);

        result.addr = _pool;
        result.expectedLiquidity = pool.expectedLiquidity();
        result.expectedLiquidityLimit = pool.expectedLiquidityLimit();
        result.availableLiquidity = pool.availableLiquidity();
        result.totalBorrowed = pool.totalBorrowed();
        result.dieselRate_RAY = pool.getDieselRate_RAY();
        result.linearCumulativeIndex = pool.calcLinearCumulative_RAY();
        result.borrowAPY_RAY = pool.borrowAPY_RAY();
        result.underlying = pool.underlying();
        result.dieselToken = pool.dieselToken();
        result.dieselRate_RAY = pool.getDieselRate_RAY();
        result.withdrawFee = pool.withdrawFee();
        result.isWETH = result.underlying == WETHToken;
        result.timestampLU = pool._timestampLU();
        result.cumulativeIndex_RAY = pool._cumulativeIndex_RAY();

        uint256 dieselSupply = IERC20(result.dieselToken).totalSupply();
        uint256 totalLP = pool.fromDiesel(dieselSupply);
        result.depositAPY_RAY = totalLP == 0
            ? result.borrowAPY_RAY
            : (result.borrowAPY_RAY * result.totalBorrowed).percentMul(
                PERCENTAGE_FACTOR - result.withdrawFee
            ) / totalLP;

        result.version = uint8(pool.version());

        return result;
    }

    /// @dev Returns PoolData for all registered pools
    function getPoolsList() external view returns (PoolData[] memory) {
        uint256 poolsCount = contractsRegister.getPoolsCount();

        PoolData[] memory result = new PoolData[](poolsCount);

        for (uint256 i = 0; i < poolsCount; i++) {
            address pool = contractsRegister.pools(i);
            result[i] = getPoolData(pool);
        }

        return result;
    }

    /// @dev Returns compressed token data for particular token.
    /// Be careful, it can be reverted for non-standart tokens which has no "symbol" method for example
    function getTokenData(address[] memory addr)
        external
        view
        returns (TokenInfo[] memory)
    {
        TokenInfo[] memory result = new TokenInfo[](addr.length);
        for (uint256 i = 0; i < addr.length; i++) {
            result[i] = TokenInfo(
                addr[i],
                ERC20(addr[i]).symbol(),
                ERC20(addr[i]).decimals()
            );
        }
        return result;
    }

    /// @dev Returns adapter address for particular creditManager and protocol
    function getAdapter(address _creditManager, address _allowedContract)
        external
        view
        registeredCreditManagerOnly(_creditManager)
        returns (address)
    {
        return address(0);
        //            ICreditManager(_creditManager).contractToAdapter(_allowedContract);
    }

    function calcExpectedHf(
        address _creditManager,
        address borrower,
        uint256[] memory balances
    ) external view returns (uint256) {
        (
            ICreditManager creditManager,
            ICreditFacade creditFacade
        ) = getCreditContracts(_creditManager);

        address creditAccount = creditManager.getCreditAccountOrRevert(
            borrower
        );

        IPriceOracle priceOracle = IPriceOracle(creditManager.priceOracle());
        uint256 tokenLength = creditManager.allowedTokensCount();
        require(balances.length == tokenLength, "Incorrect balances size");

        uint256 total = 0;
        address underlying = creditManager.underlying();

        for (uint256 i = 0; i < tokenLength; i++) {
            {
                total +=
                    priceOracle.convert(
                        balances[i],
                        creditManager.allowedTokens(i),
                        underlying
                    ) *
                    (
                        creditManager.liquidationThresholds(
                            creditManager.allowedTokens(i)
                        )
                    );
            }
        }

        (, uint256 borrowAmountWithInterest) = creditManager
        .calcCreditAccountAccruedInterest(creditAccount);

        return total / borrowAmountWithInterest;
    }

    function calcExpectedAtOpenHf(
        address _creditManager,
        address token,
        uint256 amount,
        uint256 borrowedAmount
    ) external view returns (uint256) {
        (
            ICreditManager creditManager,
            ICreditFacade creditFacade
        ) = getCreditContracts(_creditManager);

        IPriceOracle priceOracle = IPriceOracle(creditManager.priceOracle());

        uint256 total = priceOracle.convert(
            amount,
            token,
            creditManager.underlying()
        ) * (creditManager.liquidationThresholds(token));

        return total / borrowedAmount;
    }

    function getCreditContracts(address _creditManager)
        internal
        view
        registeredCreditManagerOnly(_creditManager)
        returns (ICreditManager creditManager, ICreditFacade creditFacade)
    {
        creditManager = ICreditManager(_creditManager);
        creditFacade = ICreditFacade(creditManager.creditFacade());
    }

    function _hasOpenedCreditAccount(address creditManager, address borrower)
        internal
        view
        returns (bool)
    {
        return
            ICreditManager(creditManager).creditAccounts(borrower) !=
            address(0);
    }
}
