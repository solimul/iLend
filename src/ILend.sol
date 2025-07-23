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

    event LiquidationUSDCReceived(
        address indexed liquidator,
        uint256 usdcAmount,
        uint256 poolBalance,
        uint256 timestamp
    );

    event LiquidatorReceivesETH(
        address indexed liquidator,
        uint256 ethAmount,
        uint256 poolBalance,
        uint256 timestamp
    );

    error DepositorDoesNotHaveEnoughUSDC(address depositor);
    error DepositorUSDCAllowanceTooLow(
        address depositor, 
        address depositAddress
    );
    error DepoistorUSDCTransferFromFailed(
        address depositor,
        address depositAddress,
        uint256 amount
    );

    error TransferAmountMismatchInDepositPoolAfterTransfer(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );

    error BorrowerDoesNotHaveEnoughETHCollateral(
        address borrower, 
        uint256 requiredAmount, 
        uint256 availableAmount
    );
    error BorrowerETHCollateralAllowanceTooLowForILend(
        address borrower, 
        address collateralAddress
    );
    error BorrowerETHCollateralTransferFromFailed(
        address borrower,
        address collateralAddress,
        uint256 amount
    );

    error TransferAmountMismatchInCollateralAfterTransfer(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );


    error TransferAmountMismatchInDepositPoolAfterTransferToBorrower(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );

    error TransferAmountMismatchInCollateralAfterTransferToLiquidator(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );

    error LiquidatorUSDCTransferFromFailed(
        address liquidator,
        address depositAddress,
        uint256 amount
    );

    error LiquidatorUSDCAllowanceTooLowForILend (
        address liquidator,
        address depositAddress
    );

    error LiquidatorDoesNotHaveEnoughUSDC(
        address liquidator,
        uint256 requiredAmount,
        uint256 availableAmount
    );

    error CollateralPoolDoesNotHaveEnoughETHForLiquidation(
        address collateralAddress,
        uint256 requiredAmount,
        uint256 availableAmount
    );

    error OnlyOwnerCanCallThisFunction(address caller, address owner);


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
    modifier only_owner() {
        if (msg.sender != owner) {
            revert OnlyOwnerCanCallThisFunction(msg.sender, owner);
        }
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
        
        collateral = new Collateral(pAddress, 
                        pfAddress,  
                        txAddress, 
                        ethContractAddress);

        address collateralAddress = address (collateral);

        deposit = new Deposit(pAddress, 
                            usdcContractAddress,  
                            txAddress,
                            collateralAddress);

        address depositAddress = address (deposit);                    



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
        collateral.set_liquidation_engine (address (liquidationEngine));
    } 

    function deposit_funds (uint256 _amount, uint256 _lockupPeriod) external {
        // Call the deposit function in the Deposit contract
        IERC20 token = IERC20(usdcContractAddress); 
        if (token.balanceOf (msg.sender) < _amount) {
            revert DepositorDoesNotHaveEnoughUSDC(msg.sender);
        }
        if (token.allowance(msg.sender, address(this)) < _amount){
            revert DepositorUSDCAllowanceTooLow(msg.sender, address(deposit));
        }

        uint256 currentBalance = token.balanceOf(address(deposit));

        if (token.transferFrom(msg.sender, address (deposit), _amount) == false) {
            revert DepoistorUSDCTransferFromFailed(
                msg.sender,
                address(deposit),
                _amount
            );
        }

          
        uint256 newBalance = token.balanceOf(address(deposit));
        if (newBalance < _amount + currentBalance) {
            revert TransferAmountMismatchInDepositPoolAfterTransfer(
                _amount,
                currentBalance,
                newBalance
            );
        }
        
       
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
        uint256 borrowerETHBalance = token.balanceOf(msg.sender);
        if ( borrowerETHBalance < amount) {
            revert BorrowerDoesNotHaveEnoughETHCollateral(msg.sender, amount, borrowerETHBalance);
        }

        if (borrowerETHBalance < amount){
            revert BorrowerETHCollateralAllowanceTooLowForILend(msg.sender, address(collateral));
        }
  
        collateral.update_collateral_records (msg.sender, amount);

        uint256 currentBalance = token.balanceOf(address(collateral));
        if (token.transferFrom(msg.sender, address (collateral), amount) == false) {
            revert BorrowerETHCollateralTransferFromFailed(
                msg.sender,
                address(collateral),
                amount
            );
        }

        uint256 newBalance = token.balanceOf(address(collateral));
        
        if (newBalance < currentBalance + amount) {
            revert TransferAmountMismatchInCollateralAfterTransfer(
                amount,
                currentBalance,
                newBalance
            );
        }

        emit CollateralDepositDone(
            msg.sender,
            address(collateral),
            amount,
            block.timestamp
        );
        

        if (!borrow.borrower_exists (msg.sender))
            borrow.add_new_borrower (msg.sender, 0, 0, 0, 0);
        uint256 collateralDepositCount = collateral.get_collateral_deposit_count(msg.sender);
        uint256 borrowAmount = borrow.update_borrow_records (msg.sender, collateralDepositCount-1);
        collateral.update_borrowed_against_collateral (msg.sender, collateralDepositCount-1, true);
        
        token = IERC20 (usdcContractAddress);
        currentBalance = token.balanceOf(address (deposit));
        deposit.withdraw_to_borrower (token, msg.sender, borrowAmount, msg.sender, collateralDepositCount-1);
        newBalance = token.balanceOf(address(deposit));
        if (newBalance > currentBalance - borrowAmount) {
            revert TransferAmountMismatchInDepositPoolAfterTransferToBorrower(
                borrowAmount,
                currentBalance,
                newBalance
            );
        }

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
        address [] memory list = liquidationRegistry.get_liqudation_ready_addresses (); 
        uint256 n = list.length;
        LiquidationReadyCollateral [][] memory _cols = new LiquidationReadyCollateral [][] (n);
        for (uint256 i=0; i< n; i++){
            _cols [i] = liquidationRegistry.get_liquidation_ready_collaterals_by_borrower (list [i]);
        }
        return _cols;
    }

    function liquidate_position_for_ETH 
    (
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount
    ) external {
        IERC20 token = IERC20(usdcContractAddress);
        uint256 lequidatorUSDCBalance = token.balanceOf(msg.sender);
        if (lequidatorUSDCBalance < _usdcAmount) {
            revert LiquidatorDoesNotHaveEnoughUSDC(
                msg.sender,
                _usdcAmount,
                lequidatorUSDCBalance
            );
        }

        if ( token.allowance(msg.sender, address(this))< _usdcAmount) {
            revert LiquidatorUSDCAllowanceTooLowForILend(
                msg.sender,
                address(this)
            );
        }
  
        uint256 currentBalance = token.balanceOf (address (deposit));

        if (token.transferFrom(msg.sender, address (deposit), _usdcAmount) == false) {
            revert LiquidatorUSDCTransferFromFailed(
                msg.sender,
                address(deposit),
                _usdcAmount
            );
        }

   

        uint256 newBalance = token.balanceOf (address (deposit));

        if (newBalance < currentBalance + _usdcAmount) {
            revert TransferAmountMismatchInDepositPoolAfterTransfer(
                _usdcAmount,
                currentBalance,
                newBalance
            );
        }

        emit LiquidationUSDCReceived(
            msg.sender,
            _usdcAmount,
            currentBalance + _usdcAmount,
            block.timestamp
        );

        uint256 ethAmount 
            = liquidationEngine.update_on_liquidation_deposit (msg.sender, _borrower, _loanID, _usdcAmount);

        token = IERC20 (ethContractAddress);
        currentBalance = token.balanceOf(address (collateral));

        if (token.balanceOf (address(collateral)) < ethAmount) {
            revert CollateralPoolDoesNotHaveEnoughETHForLiquidation(
                address(collateral),
                ethAmount,
                token.balanceOf(address(collateral))
            );
        }
        collateral.withdraw_to_liquidator (token, msg.sender, ethAmount, _borrower, _loanID);
        newBalance = token.balanceOf(address(collateral));
        if (newBalance > currentBalance - ethAmount) {
            revert TransferAmountMismatchInCollateralAfterTransferToLiquidator(
                ethAmount,
                currentBalance,
                newBalance
            );
        }

        liquidationEngine.set_liquidated_status(_borrower, _loanID, true);
        emit LiquidatorReceivesETH(
            msg.sender,
            ethAmount,
            newBalance,
            block.timestamp
        );

    }
}