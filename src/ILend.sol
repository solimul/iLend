//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./misc/Params.sol";
import {Deposit} from "./deposit/Deposit.sol";
import {Collateral} from "./collateral/Collateral.sol";
import {Borrow} from "./borrow/Borrow.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./helper/PriceConverter.sol";
import {PricefeedManagerLib} from "./lib/PricefeedManagerLib.sol";
import {CollateralView, LiquidationReadyCollateral} from "./shared/SharedStructures.sol";
import {Treasury} from "./treasury/Treasury.sol";
import {NetworkConfigLib} from "./lib/NetworkConfigLib.sol";
import {Payback} from "./repayment/Payback.sol";
import {Transaction} from "./misc/Transcation.sol";
import {Monitor} from "./liquidation/Monitor.sol";
import {LiquidationRegistry} from "./liquidation/LiquidationRegistry.sol";
import {LiquidationEngine} from "./liquidation/LiquidationEngine.sol";


import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
 

contract iLend {
    event LendingDone(
        address indexed borrower,
        uint256 amount,
        uint256 timestamp
    );
    event CollateralDepositDone(
        address indexed depositor,
        address indexed depositedTo,
        uint256 amount,
        uint256 timestamp
    );

    event FundDepoistDone(
        address indexed depositor,
        uint256 amount,
        uint256 timestamp
    );

    Params private params;   
    address private owner;
    Deposit private deposit;
    Collateral private collateral;
    Borrow private borrow;
    Treasury private treasury;
    Payback private payback;
    Transaction private transaction;
    Monitor private monitor;
    AggregatorV3Interface private priceFeed;
    LiquidationRegistry private liquidationRegistry;
    LiquidationEngine private liquidationEngine;

    address private usdcContractAddress;
    address private ethContractAddress;
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // modifier token_type_check (string memory token, string memory expectedToken) {
    //     string memory message = keccak256(abi.encodePacked("Sent ", token, ", expected ", expectedToken));
    //     require(keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked(expectedToken)), message);
    //     _;
    // }

    constructor () {
        owner = msg.sender;
        params = new Params(msg.sender, false, false, false);
        params.set_params ();
        priceFeed = AggregatorV3Interface(PricefeedManagerLib.get_price_feed_address());

        address pAddress = address (params);
        address pfAddress = address (priceFeed);
        usdcContractAddress = NetworkConfigLib.get_usdc_contract_address();
        ethContractAddress = NetworkConfigLib.get_usdc_contract_address();

        transaction = new Transaction (usdcContractAddress, ethContractAddress);

        address txAddress = address (transaction);
        
        treasury = new Treasury (owner, address (txAddress));
        
        address trAddress = address (treasury);
        
        deposit = new Deposit(pAddress, 
                            usdcContractAddress,  
                            txAddress);

        address depositAddress = address (deposit);                    

        collateral = new Collateral(pAddress, 
                        pfAddress,  
                        txAddress, 
                        ethContractAddress);

        address collateralAddress = address (collateral);

        borrow = new Borrow(pAddress, 
                    pfAddress, 
                    depositAddress, 
                    collateralAddress, 
                    usdcContractAddress, 
                    txAddress);

        address borrowAddress = address (borrow);

        payback = new Payback (borrowAddress, 
                              depositAddress, 
                              trAddress, 
                              usdcContractAddress,
                             txAddress);

        liquidationRegistry = new LiquidationRegistry ();

        address liqRegAddress = address (liquidationRegistry);

        monitor = new Monitor (pAddress,
                        pfAddress,
                        collateralAddress,
                        address (this),
                        liqRegAddress);

        liquidationEngine = new LiquidationEngine (liqRegAddress,
                        collateralAddress,
                        depositAddress, 
                        txAddress);
    } 

    function deposit_funds (uint256 _amount, uint256 _lockupPeriod) external {
        // Call the deposit function in the Deposit contract
        IERC20 token = IERC20(usdcContractAddress); 
        require (token.balanceOf (msg.sender) >= _amount, "Depositor does not have enough USDC");
        require(
            token.allowance(msg.sender, address(this)) >= _amount,
            "TOKEN: allowance too low"
        );
        uint256 currentBalance = token.balanceOf(address(deposit));

        require(
            token.transferFrom(msg.sender, address (deposit), _amount),
            "USDC transfer to the deposit pool failed"); 
          
        uint256 newBalance = token.balanceOf(address(deposit));

        require (newBalance >= _amount + currentBalance, "Deposit amount mismatch after transfer of USDC to the deposit pool");
       
        deposit.update_post_deposit (msg.sender, _amount, _lockupPeriod);

        emit FundDepoistDone (
            msg.sender,
            _amount,
            block.timestamp
        );
    } 

    function withdraw_deposited_principal (uint256 amount) external {
        // Call the withdraw function in the Deposit contract
        deposit.withdraw_principal (msg.sender, amount);
    }

    function withdraw_deposited_interest (uint256 amount) external {
        // Call the withdraw interest function in the Deposit contract
        deposit.withdraw_interest(msg.sender, amount);
    }


   function deposit_collateral_borrow (uint256 amount) 
    external {
        // Call the deposit function in the Deposit contract
        IERC20 token = IERC20(ethContractAddress);
        require (token.balanceOf (msg.sender) >= amount, "Borrower Does not have enough ETH collaterals");
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            "TOKEN: allowance too low"
        );
        collateral.update_collateral_records (msg.sender, amount);

        uint256 currentBalance = token.balanceOf(address(collateral));
        require(
            token.transferFrom(msg.sender, address (collateral), amount), 
            "TOKEN: transferFrom failed"
        );
        uint256 newBalance = token.balanceOf(address(collateral));
        
        require(newBalance == currentBalance + amount, "Collateral deposit (ETH) amount mismatch after transfer");

        emit CollateralDepositDone(
            msg.sender,
            address(collateral),
            amount,
            block.timestamp
        );
        

        if (!borrow.borrower_exists (msg.sender))
            borrow.add_new_borrower (msg.sender, 0, 0, 0, 0);
            
        uint256 borrowAmount = borrow.update_borrow_records (msg.sender, collateral.get_collateral_depositors_deposit_count(msg.sender)-1);
        collateral.update_borrowed_against_collateral (msg.sender, collateral.get_collateral_depositors_deposit_count(msg.sender)-1, true);
        
        token = IERC20 (usdcContractAddress);
        currentBalance = token.balanceOf(address (deposit));
        deposit.withdraw_to (token, msg.sender, borrowAmount);
        newBalance = token.balanceOf(address(deposit));
        require(newBalance == currentBalance - borrowAmount, "USDC borrow amount mismatch after transfer to borrower");

        emit LendingDone(
            msg.sender,
            borrowAmount,
            block.timestamp
        );
    }

    function get_my_collateral_info () external returns (CollateralView [] memory) {
        // Call the view function in the Collateral contract
        collateral.set_borrower_contract(address (borrow));
        return collateral.get_collateral_depositor_info(msg.sender);
    }

    function close_loan (uint256 _loanID) external payable {
        payback.process_repayment (msg.sender, _loanID, msg.value);
        collateral.unlock_collateral (msg.sender, _loanID);
    }

    function get_liquidation_ready_collaterals () 
    external view returns (LiquidationReadyCollateral [] [] memory) {
        address [] memory list = liquidationRegistry.get_list_of_liqudation_ready_addresses (); 
        uint256 n = list.length;
        LiquidationReadyCollateral [][] memory _cols = new LiquidationReadyCollateral [][] (n);
        for (uint256 i=0; i< n; i++){
            _cols [i] = liquidationRegistry.get_liquidation_ready_collateral_information_for_the_borrower (list [i]);
        }
        return _cols;
    }

    function inject_liquid_against_undercollateralized_borrow 
    (
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount
    ) external {
        liquidationEngine.inject_liquid_send_discounted_collateral(msg.sender, _borrower, _loanID, _usdcAmount);
    }
}