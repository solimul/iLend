// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Script} from "../lib/forge-std/src/Script.sol";


import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PricefeedManagerLib} from "../src/lib/PricefeedManagerLib.sol";
import {NetworkConfigLib} from "../src/lib/NetworkConfigLib.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Borrow module
import "../src/borrow/Borrow.sol";

// Collateral module
import "../src/collateral/Collateral.sol";
import "../src/collateral/CollateralPool.sol";

// Deposit module
import "../src/deposit/Deposit.sol";
import "../src/deposit/DepositPool.sol";

// Liquidation module
import "../src/liquidation/LiquidationEngine.sol";
import "../src/liquidation/LiquidationRegistry.sol";
import "../src/liquidation/Monitor.sol";

// Misc module
import "../src/misc/Params.sol";
import "../src/misc/ProtocolReward.sol";
import "../src/misc/Transcation.sol";

// Repayment module
import "../src/repayment/Payback.sol";

// Treasury module
import "../src/treasury/Treasury.sol";

// Shared interface
import {iLend} from "../src/ILend.sol";


contract UnitTest is Test {
    Borrow private borrow;
    Collateral private collateral;
    CollateralPool private collateralPool;
    Deposit private deposit;
    DepositPool private depositPool;
    LiquidationEngine private liquidationEngine;
    LiquidationRegistry private liquidationRegistry;
    Monitor private monitor;
    Params private params;
    ProtocolReward private protocolReward;
    Transaction private transaction;
    Payback private payback;
    Treasury private treasury;
    iLend private lendProtocol;
    AggregatorV3Interface private priceFeed;
    address private usdcAddress;
    address private wrappedETHAddress;

    uint256 private constant NFUNDERS = 5;
    uint256 private constant NBORROWERS = 5;
    uint256 private constant NLIQUIDATORS = 5;

    uint256 private constant FUNDERS_INIT_USDC_FUNDS = 100e8;
    uint256 private constant FUNDERS_INIT_ETH_FUNDS = 0;

    uint256 private constant BORROWERS_INIT_USDC_FUNDS = 0;
    uint256 private constant BORROWERS_INIT_ETH_FUNDS = 100 ether;

    uint256 private constant LIQUIDATORS_INIT_USDC_FUNDS = 1000e8;
    uint256 private constant LIQUIDATORS_INIT_ETH_FUNDS = 0;


    uint256 private constant ZERO = 0;






    struct Actor {
        address actor;
        uint256 wrappedETHBalance;
        uint256 usdcBalance;
    }

    Actor [] private borrowers;
    Actor [] private funders;
    Actor [] private liquidators;

    function setUp() public virtual {
        params = new Params(false, false, false);
        params.set_params();

        priceFeed = AggregatorV3Interface(PricefeedManagerLib.get_price_feed_address());
        usdcAddress = NetworkConfigLib.get_usdc_contract_address();
        wrappedETHAddress = NetworkConfigLib.get_usdc_contract_address();

        transaction = new Transaction(usdcAddress, wrappedETHAddress);
        address txAddress = address(transaction);

        treasury = new Treasury();
        address trAddress = address(treasury);
        address pAddress = address(params);
        address pfAddress = address(priceFeed);

        collateral = new Collateral(pAddress, pfAddress, txAddress, wrappedETHAddress);
        address colAddress = address(collateral);

        deposit = new Deposit(pAddress, usdcAddress, txAddress, colAddress);
        address depAddress = address(deposit);

        borrow = new Borrow(pAddress, pfAddress, depAddress, colAddress, usdcAddress, txAddress);
        address borrowAddress = address(borrow);

        payback = new Payback(borrowAddress, depAddress, trAddress, usdcAddress);

        liquidationRegistry = new LiquidationRegistry();
        address liqRegAddress = address(liquidationRegistry);

        monitor = new Monitor(pAddress, pfAddress, colAddress, address(this), liqRegAddress);

        liquidationEngine = new LiquidationEngine(liqRegAddress, colAddress, depAddress, txAddress);

        address paybackAddress = address(payback);
        address monitorAddress = address(monitor);
        address liqEngineAddress = address(liquidationEngine);

        lendProtocol = new iLend(
            pAddress,
            pfAddress,
            usdcAddress,
            wrappedETHAddress,
            trAddress,
            colAddress,
            depAddress,
            borrowAddress,
            paybackAddress,
            liqRegAddress,
            monitorAddress,
            liqEngineAddress
        );

        setup_facade_contract ();

        setup_and_fund 
        (
            NFUNDERS, 
            "Funder", 
            FUNDERS_INIT_USDC_FUNDS, 
            FUNDERS_INIT_ETH_FUNDS, 
            funders
        );
        setup_and_fund 
        (
            NBORROWERS, 
            "Borrower", 
            BORROWERS_INIT_USDC_FUNDS, 
            BORROWERS_INIT_ETH_FUNDS, 
            borrowers
        );
        setup_and_fund 
        (
            NLIQUIDATORS, 
            "Liquidator", 
            LIQUIDATORS_INIT_USDC_FUNDS, 
            LIQUIDATORS_INIT_ETH_FUNDS, 
            liquidators
        );

    }

    function setup_facade_contract () internal {
        params.set_facade_contract (lendProtocol);
        treasury.set_facade_contract (lendProtocol);
        borrow.set_facade_contract(lendProtocol);
        collateral.set_facade_contract (lendProtocol);
        deposit.set_facade_contract (lendProtocol);
        payback.set_facade_contract (lendProtocol);
        liquidationRegistry.set_facade_contract (lendProtocol);
        liquidationEngine.set_facade_contract (lendProtocol);
        monitor.set_facade_contract (lendProtocol);
    }

    function setup_and_fund 
    (
        uint256 _cnt, 
        string memory _type,  
        uint256 _initFundsUSDC,
        uint256 _initFundsETH,
        Actor [] storage actors
    ) 
    internal {
        for (uint256 i=0; i<_cnt; i++){
            string memory label = string(abi.encodePacked(_type,"_", vm.toString(i)));
            address actorAddress = makeAddr (label);
            uint256 usdcAmount = _initFundsUSDC* (i+1);
            deal (usdcAddress, actorAddress, usdcAmount);
            uint256 ethAmount = _initFundsETH* (i+1);
            deal (wrappedETHAddress, actorAddress, ethAmount);

            vm.startPrank(actorAddress);
            IERC20(usdcAddress).approve(address(lendProtocol), type(uint256).max);
            IERC20(usdcAddress).approve(address(lendProtocol), type(uint256).max);
            IERC20(usdcAddress).approve(address(lendProtocol), type(uint256).max);
            IERC20(wrappedETHAddress).approve(address(lendProtocol), type(uint256).max);
            vm.stopPrank();

            actors.push 
                (
                    Actor 
                    (
                        {
                            actor:actorAddress, 
                            usdcBalance:usdcAmount, 
                            wrappedETHBalance:ethAmount
                        }
                    )
                );
        }
    }


    function test_each_funders_init_balance () public view {
        //console.log ("Reached here");
        for (uint256 i=0; i<NFUNDERS; i++){
            Actor memory funder = funders [i];
            //console.log ("Reached here", IERC20(usdcAddress).balanceOf(funder.actor));

            assert(IERC20(usdcAddress).balanceOf(funder.actor) == funder.usdcBalance);
            assert(IERC20(wrappedETHAddress).balanceOf(funder.actor) == 0);
        }
    }

    function test_each_borrowers_init_balance () public view {
        //console.log ("Reached here");
        for (uint256 i=0; i<NBORROWERS; i++){
            Actor memory borrower = borrowers [i];
            //console.log ("Reached here", IERC20(wrappedETHAddress).balanceOf(borrower.actor));

            assert(IERC20(usdcAddress).balanceOf(borrower.actor) == 0);
            assert(IERC20(wrappedETHAddress).balanceOf(borrower.actor) == borrower.wrappedETHBalance);
        }
    }

    function test_each_liquidators_init_balance () public view {
    //console.log ("Reached here");
        for (uint256 i=0; i<NLIQUIDATORS; i++){
            Actor memory liquidator = liquidators [i];
            //console.log ("Reached here", IERC20(usdcAddress).balanceOf(liquidator.actor));

            assert(IERC20(usdcAddress).balanceOf(liquidator.actor) == liquidator.usdcBalance);
            assert(IERC20(wrappedETHAddress).balanceOf(liquidator.actor) == 0);
        }
    }

    function test_deposit_my_funds () public {
        Actor memory funder = funders [0];
        vm.startPrank (funder.actor);
        uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
        uint256 amount = funderUSDCBalance/2;
        uint256 currentBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
        lendProtocol.deposit_my_funds (amount, 365 days); 
        uint256 updatedBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
        console.log ((IERC20 (usdcAddress)).balanceOf (address (funder.actor)), funderUSDCBalance , amount);
        assert (updatedBalance == currentBalance + amount);
        assert ((IERC20 (usdcAddress)).balanceOf (address (funder.actor)) == funderUSDCBalance - amount);
    }

      function test_deposit_my_funds_multiple () public {
        uint256 total = 0;
        uint256 totalUpdated = 0;
        uint256 totalCurrent = 0;
        for (uint256 i=0; i< funders.length; i++){
            Actor memory funder = funders [i];
            vm.startPrank (funder.actor);
            uint256 amount = funder.usdcBalance/2;
            uint256 currentBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
            lendProtocol.deposit_my_funds (amount, 365 days); 
            uint256 updatedBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
            console.log (updatedBalance, currentBalance, amount);
            total += amount;
            totalUpdated += updatedBalance;
            totalCurrent += currentBalance;
            vm.stopPrank();
        }
        console.log (totalUpdated, totalCurrent, total);
        assert (totalUpdated == totalCurrent + total);
    }

}
