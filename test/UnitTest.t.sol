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

import {PriceConverter} from "../src/helper/PriceConverter.sol";

contract UnitTest is Test {
    using PriceConverter for uint256;

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

    uint256 private constant FUNDERS_INIT_USDC_FUNDS = 100_00e6; // 10000 USDC: 
    uint256 private constant FUNDERS_INIT_ETH_FUNDS = 0;

    uint256 private constant BORROWERS_INIT_USDC_FUNDS = 0;
    uint256 private constant BORROWERS_INIT_ETH_FUNDS = 10e18; // 10 ether

    uint256 private constant LIQUIDATORS_INIT_USDC_FUNDS = 100_00e6; // 10000 usdc
    uint256 private constant LIQUIDATORS_INIT_ETH_FUNDS = 0;


    uint256 private constant ZERO = 0;
    uint256 private constant HUNDRED = 100;
    uint256 private constant DEFAULT_COLLATERAL_PERCENTAGE = 10;
    uint256 private constant ETHER_IN_WEI = 1e18;
    uint256 private constant USDC_IN_WEI = 1e6;

    uint256 private constant NBORROWERS_TO_TEST = 5;
    uint256 private constant NCOLLATERALDEPOSIT_TO_TEST = 3;



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
        set_params();

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

    function set_params () internal {
        params.set_deposit_params (100e6, 100_000_0e6, 0, 1 days, 365 days);
        params.set_borrow_params (1000, 1000000, 50, 1 days, 365 days, 5, 20, 200, 50);
        params.set_liquidation_params (150, 10, 1000, 50000, 1000, 50000, 5, "percentage");
        params.set_oracle_params (address(this), 60 seconds, 18);
        params.set_collateral_params (address(this), 1e18, 1000e18, 75, true);
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
            uint256 usdcAmount = (_initFundsUSDC* (i+1));
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

    /***
     * ***** deposit_my_funds test 
    */

    function test_init_funder_balances () public view {
        //console.log ("Reached here");
        for (uint256 i=0; i<NFUNDERS; i++){
            Actor memory funder = funders [i];
            //console.log ("Reached here", IERC20(usdcAddress).balanceOf(funder.actor));

            assert(IERC20(usdcAddress).balanceOf(funder.actor) == funder.usdcBalance);
            assert(IERC20(wrappedETHAddress).balanceOf(funder.actor) == 0);
        }
    }

    

    function test_deposit_balance_change () public {
        Actor memory funder = funders [0];
        vm.startPrank (funder.actor);
        uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
        uint256 amount = funderUSDCBalance/2;
        uint256 currentBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
        lendProtocol.deposit_my_funds (amount, 365 days); 
        uint256 updatedBalance = (IERC20 (usdcAddress)).balanceOf (address (deposit));
        //console.log ((IERC20 (usdcAddress)).balanceOf (address (funder.actor)), funderUSDCBalance , amount);
        assert (updatedBalance == currentBalance + amount);
        assert ((IERC20 (usdcAddress)).balanceOf (address (funder.actor)) == funderUSDCBalance - amount);
    }

      function test_deposit_balance_change_all_funders () public {
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
            //console.log (updatedBalance, currentBalance, amount);
            total += amount;
            totalUpdated += updatedBalance;
            totalCurrent += currentBalance;
            vm.stopPrank();
        }
        //console.log (totalUpdated, totalCurrent, total);
        assert (totalUpdated == totalCurrent + total);
    }

    function test_deposit_state_single () public {
        Actor memory funder = funders [0];

        (uint256 ta0, uint256 iwr0, uint256 pwr0, bool ia0, uint256 dc0) 
                =deposit.test_get_depositor_deposit_attributes (funder.actor);

        vm.startPrank (funder.actor);
        uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
        uint256 amount = funderUSDCBalance/2;
        lendProtocol.deposit_my_funds (amount, 365 days); 
        (uint256 ta1, uint256 iwr1, uint256 pwr1, bool ia1, uint256 dc1) 
                =deposit.test_get_depositor_deposit_attributes (funder.actor);

        assert (ta1 == ta0 +amount);
        assert (iwr0 == iwr1);
        assert (pwr0 == pwr1);
        assert (ia0 == false && ia1 == true);
        assert (dc0 == 0);
        assert (dc1 == dc0 + 1);
    }

    function test_deposit_state_multiple () public {
        for (uint i = 0; i < 10; i++) {
            Actor memory funder = funders[0];

            (uint256 ta0, uint256 iwr0, uint256 pwr0, bool ia0, uint256 dc0) = 
                deposit.test_get_depositor_deposit_attributes(funder.actor);

            vm.startPrank(funder.actor);
            uint256 funderUSDCBalance = IERC20(usdcAddress).balanceOf(address(funder.actor));
            uint256 amount = funderUSDCBalance / 2;
            lendProtocol.deposit_my_funds(amount, 365 days);

            (uint256 ta1, uint256 iwr1, uint256 pwr1, bool ia1, uint256 dc1) = 
                deposit.test_get_depositor_deposit_attributes(funder.actor);

            console.log("Iteration %s", i);
            console.log("  ta  %s : %s", ta0, ta1);
            console.log("  iwr %s : %s", iwr0, iwr1);
            console.log("  pwr %s : %s", pwr0, pwr1);
            console.log("  ia  %s : %s", ia0, ia1);
            console.log("  dc  %s : %s", dc0, dc1);

            assert(ta1 == ta0 + amount);
            assert(iwr0 == iwr1);
            assert(pwr0 == pwr1);
            if (i == 0)
                assert(ia0 == false && ia1 == true);
            else
                assert(ia0 == true && ia1 == true);
            assert(dc1 == dc0 + 1);
        }
    }



    function test_deposit_record_single () public {
        Actor memory funder = funders [0];
        vm.startPrank (funder.actor);
        uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
        uint256 amount = funderUSDCBalance/2;
        lendProtocol.deposit_my_funds (amount, 365 days); 
        (uint256 am, 
         uint256 lp,
         uint256 atl,
         uint256 iec) 
         = deposit.test_get_depositor_deposit_record_attributes (funder.actor, 0);
        assert (am == amount);
        assert (lp == 365 days);
        assert (atl == amount);
        assert (iec == 0);
    }

    function test_deposit_record_multiple () public { 
        uint256 am = 0; 
        uint256 lp = 0;
        uint256 atl = 0;
        uint256 iec =0; 
        for (uint i = 0; i < 10; i++) {
            Actor memory funder = funders[0];
            vm.startPrank (funder.actor);
            uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
            uint256 amount = funderUSDCBalance/2;
            lendProtocol.deposit_my_funds (amount, 365 days); 
            (am, 
            lp,
            atl,
            iec) 
            = deposit.test_get_depositor_deposit_record_attributes (funder.actor, i);
            assert (am == amount);
            assert (lp == 365 days);
            assert (atl == amount);
            assert (iec == 0);
        }
    }



    

    function test_deposit_state_multi_funders () public {
       (uint256 ta00, uint256 iw00, uint256 pwr00, bool ia00, uint256 dc00, uint256 amount00)  = fund_it (0);
       (uint256 ta10, uint256 iw10, uint256 pwr10, bool ia10, uint256 dc10, uint256 amount10) = fund_it(1);
       (uint256 ta01, uint256 iw01, uint256 pwr01, bool ia01, uint256 dc01, uint256 amount01)  = fund_it (0);
       (uint256 ta02, uint256 iw02, uint256 pwr02, bool ia02, uint256 dc02, uint256 amount02)  = fund_it (0);
       (uint256 ta11, uint256 iw11, uint256 pwr11, bool ia11, uint256 dc11, uint256 amount11) = fund_it(1);
       (uint256 ta12, uint256 iw12, uint256 pwr12, bool ia12, uint256 dc12, uint256 amount12) = fund_it(1);

        assert (
                    ta00 == amount00 
                    && iw00 == 0
                    && pwr00 == 0
                    && ia00 == true
                    && dc00 == 1
               );
        
        assert (
                    ta01 == ta00 + amount01 
                    && iw01 == 0
                    && pwr01 == 0
                    && ia01 == true
                    && dc01 == dc00 + 1
               );

        assert (
                ta02 == ta01 + amount02 
                && iw02 == 0
                && pwr02 == 0
                && ia02 == true
                && dc02 == dc01 + 1
            );

            assert (
            ta10 == amount10
            && iw10 == 0
            && pwr10 == 0
            && ia10 == true
            && dc10 == 1
        );

        assert (
            ta11 == ta10 + amount11
            && iw11 == 0
            && pwr11 == 0
            && ia11 == true
            && dc11 == dc10 + 1
        );

        assert (
            ta12 == ta11 + amount12
            && iw12 == 0
            && pwr12 == 0
            && ia12 == true
            && dc12 == dc11 + 1
        );
        assert ((IERC20 (usdcAddress)).balanceOf (address (deposit)) 
                == amount00+amount01+amount02+amount10+amount11+amount12);    
    }

    function fund_it (uint256 _funderIndex) 
    public 
    returns (uint256 ta, uint256 iwr, uint256 pwr, bool ia, uint256 dc, uint256 amount) {
        Actor memory funder = funders [_funderIndex];
        vm.startPrank (funder.actor);
        uint256 funderUSDCBalance = (IERC20 (usdcAddress)).balanceOf (address (funder.actor));
        amount = funderUSDCBalance/2;
        lendProtocol.deposit_my_funds (amount, 365 days); 
        (ta, iwr, pwr, ia, dc) 
        = deposit.test_get_depositor_deposit_attributes (funder.actor);
        vm.stopPrank ();
    }

    /** 
        deposit_collateral_borrow testing
    */

    function test_init_borrower_balances () public view {
        for (uint256 i=0; i<NBORROWERS; i++){
            Actor memory borrower = borrowers [i];

            assert(IERC20(usdcAddress).balanceOf(borrower.actor) == 0);
            assert(IERC20(wrappedETHAddress).balanceOf(borrower.actor) == borrower.wrappedETHBalance);
        }
    }

    function test_collateral_balance_change () public {
        uint256 depBalance0 = IERC20(usdcAddress).balanceOf (address (deposit));
        uint256 totalDeposited = seed_deposit_pool ();
        uint256 depBalance1 = IERC20(usdcAddress).balanceOf (address (deposit));
        assert (totalDeposited + depBalance0 == depBalance1);
        
        Actor storage borrower = borrowers [0]; 
        uint256 colBalance0 = IERC20 (wrappedETHAddress).balanceOf (address (collateral));
        uint256 borrowerBalance0 = IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor));
        uint256 ethAmount = borrowerBalance0/2;
        execute_collateral_deposit (borrower.actor, ethAmount);
        // vm.startPrank (borrower.actor);

        //     //console.log ("====>", borrower.actor, borrowerBalance0);
        //     lendProtocol.deposit_collateral (ethAmount);
        // vm.stopPrank ();
        uint256 borrowerBalance1 = IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor));
        uint256 colBalance1 = IERC20 (wrappedETHAddress).balanceOf (address (collateral));
        bool colInv = colBalance1 == colBalance0 + ethAmount;
        bool borInv = borrowerBalance1 == borrowerBalance0 - ethAmount;
        assert (colInv == true);
        assert (borInv == true);
    }


    


    

    function test_borrow_balance_change () public {
        seed_deposit_pool ();
        uint256 depBalance0 = IERC20 (usdcAddress).balanceOf (address (deposit));
        Actor storage borrower = borrowers [0]; 
        uint256 borrowerETHBalance0 = IERC20 (wrappedETHAddress).balanceOf (address (address (borrower.actor)));
        uint256 borrowerUSDCBalance0 = IERC20 (usdcAddress).balanceOf (address (address (borrower.actor)));
        uint256 collateralAmount =  IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor))/2;
        uint256 colBalance0 = IERC20 (wrappedETHAddress).balanceOf (address (collateral));
        
        // vm.startPrank (borrower.actor);
        //     lendProtocol.deposit_collateral (collateralAmount);    
        //     uint256 borrowAmount = lendProtocol.borrow_usdc ();
        // vm.stopPrank ();
        execute_collateral_deposit (borrower.actor, collateralAmount);
        uint256 borrowAmount = execute_borrow (borrower.actor);

        uint256 depBalance1 = IERC20 (usdcAddress).balanceOf (address (deposit));
        uint256 colBalance1 = IERC20 (wrappedETHAddress).balanceOf (address (collateral));
        uint256 borrowerETHBalance1 = IERC20 (wrappedETHAddress).balanceOf (address (address (borrower.actor)));
        uint256 borrowerUSDCBalance1 = IERC20 (usdcAddress).balanceOf (address (address (borrower.actor)));


        bool depInv = depBalance0 - borrowAmount == depBalance1;
        bool colInv = colBalance0 + collateralAmount == colBalance1;
        bool borETHInv =  borrowerETHBalance1 == borrowerETHBalance0 - collateralAmount;
        bool borUSDCInv = borrowerUSDCBalance1 == borrowerUSDCBalance0 + borrowAmount;
        
        assert (depInv == true);
        assert (colInv == true);
        assert (borETHInv == true);
        assert (borUSDCInv == true);
    }


    function test_collateral_state_change_on_deposit () public {
        seed_deposit_pool ();
        Actor storage borrower = borrowers [0]; 
        (uint256 ta0, uint256 cwrCount0, bool ia0, uint256 dc0) = collateral.test_get_collateral_depositor_state (borrower.actor);
        uint256 collateralAmount =  IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor))/2;
        execute_collateral_deposit (borrower.actor, collateralAmount);
        //uint256 borrowAmount = execute_collateral_deposit (borrower.actor);
        (uint256 ta1, uint256 cwrCount1, bool ia1, uint256 dc1) = collateral.test_get_collateral_depositor_state (borrower.actor);
        assert (ta1 == ta0  + collateralAmount);
        assert (cwrCount0 == 0 && cwrCount1 == 0);
        assert (ia0 == false && ia1 == true);
        assert (dc0 == 0);
        assert (dc1 == dc0 +1);
    }

    function helper_check_balance 
    (
        uint256 _index,
        uint256 _recordID 
    ) 
    public {
        Actor storage borrower = borrowers [_index]; 
        uint256 collateralAmount =  IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor))/2;
        execute_collateral_deposit (borrower.actor, collateralAmount);
        (uint256 amnt, uint256 l2b, bool hasBorrowedAgainst) = collateral.test_get_collateral_deposit_record_state (borrower.actor, _recordID);

        assert (amnt == collateralAmount);
        assert (l2b == params.get_l2b ());
        assert (hasBorrowedAgainst == false);
    }



    function test_collateral_record_state_change_multiple () public {
        for (uint256 i=0; i< NBORROWERS_TO_TEST; i++){
            for (uint256 j=0; j< NCOLLATERALDEPOSIT_TO_TEST; j++) {
                console.log ("borrower :",i, " record: ",j);
                helper_check_balance (i, j);
            }
        } 
    }

    function test_collateral_counts_consistency () public {
        for (uint256 i=0; i< NBORROWERS_TO_TEST; i++){
            for (uint256 j=0; j< NCOLLATERALDEPOSIT_TO_TEST; j++) {
                console.log ("borrower :",i, " record: ",j);
                helper_check_balance (i, j);
            }
            assert (collateral.get_num_records_for_collateral_deposotor (borrowers [i].actor) == NCOLLATERALDEPOSIT_TO_TEST);
        } 
        assert (collateral.get_num_collateral_depositors () == NBORROWERS_TO_TEST);
    }


    function test_borrow_state_update_single () public {
        seed_deposit_pool ();
        Actor storage borrower = borrowers [0]; 
        uint256 collateralAmount =  IERC20 (wrappedETHAddress).balanceOf (address (borrower.actor))/2;
        execute_collateral_deposit (borrower.actor, collateralAmount);
        uint256 borrowAmount = execute_borrow (borrower.actor);

        (uint256 borrowerCount,
        uint256 totalBorrowed,
        uint256 borrowCount,
        address borrowerAddress) = borrow.test_get_borrower_record_attributes (borrower.actor);
        console.log ("====>", totalBorrowed, borrowAmount);

        assert (borrowerCount == 1);
        assert (totalBorrowed == borrowAmount);
        assert (borrowCount == 1);
        assert (borrowerAddress == borrower.actor);
    }

    function execute_collateral_deposit 
    (
        address _borrower,
        uint256 _colAmount 
    ) 
    private {
        vm.startPrank (_borrower);
            lendProtocol.deposit_collateral (_colAmount);    
        vm.stopPrank ();
    }

    function execute_borrow
    (
        address _borrower
    ) 
    private
    returns (uint256 borrowAmount) {
        vm.startPrank (_borrower);
            borrowAmount = lendProtocol.borrow_usdc ();
        vm.stopPrank ();
    }

    function seed_deposit_pool () public returns (uint256 totalDeposited){
        totalDeposited = 0;
        for (uint256 i=0; i<NFUNDERS; i++) {
            (uint256 dep,,,,,) = fund_it (i);
            totalDeposited += dep;
        }
    }



}
