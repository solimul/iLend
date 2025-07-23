//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./misc/Params.sol";
import {Deposit} from "./deposit/Deposit.sol";
import {Collateral} from "./collateral/Collateral.sol";
import {Borrow} from "./borrow/Borrow.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./helper/PriceConverter.sol";
import {PricefeedManagerLib} from "./lib/PricefeedManagerLib.sol";
import {CollateralView, LiquidationReadyCollateral, RepaymentComponent} from "./shared/SharedStructures.sol";
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

    error DoesNotHaveEnoughUSDC (
        address from, 
        string fromName, 
        address to, 
        string toName, 
        uint256 amount
    );
    error DoesNotHaveEnoughAllowance (
        address from, 
        string fromName, 
        address to, 
        string toName, 
        uint256 amount
    );

    error TransferFromFailed(
        string tokenName,
        address from,
        string fromName,
        address to,
        string toName,
        uint256 amount
    );

    error TransferAmountMismatchInDepositPoolAfterIncomingTransfer_Deposit(
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


    error TransferAmountMismatchInDepositPoolAfterOutgingTransfer_Borrower(
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

    error OnlyOwnerCanCallThisFunction(address caller, address i_owner);
    error TransferAmountMismatchInDepositPoolAfterIncomingTransfer_Liquidation(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );

    error BalanceMismatchAfterIncomingTransfer(
        string tokenName,
        address from,
        string fromName,
        address to,
        string toName,
        uint256 amount,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );


    Params immutable private i_params;   
    address immutable private i_owner;
    Deposit immutable private deposit;
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

    string constant USDCSTR = "USDC";
    string constant DEPOSITORSTR = "Depositor";
    string constant DEPOSITCONTRACTSTR = "DepositContract";
    string constant ILENDSTR = "iLend";
    string constant ETHSTR = "ETH";
    string constant COLLATERALPROVIDERSTR = "CollateralProvider";
    string constant COLLATERALCONTRACTSTR = "CollateralContract";
    string constant BORROERCONTRACTSTR = "BorrowerContract";
    string constant TREASURYCONTRACTSTR = "TreasuryContract";
    
    // Modifiers
    modifier only_owner() {
        if (msg.sender != i_owner) {
            revert OnlyOwnerCanCallThisFunction(msg.sender, i_owner);
        }
        _;
    }

    // modifier token_type_check (string memory token, string memory expectedToken) {
    //     string memory message = keccak256(abi.encodePacked("Sent ", token, ", expected ", expectedToken));
    //     require(keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked(expectedToken)), message);
    //     _;
    // }

    constructor () {
        i_owner = msg.sender;
        i_params = new Params(msg.sender, false, false, false);
        i_params.set_params ();
        priceFeed = AggregatorV3Interface(PricefeedManagerLib.get_price_feed_address());

        address pAddress = address (i_params);
        address pfAddress = address (priceFeed);
        usdcContractAddress = NetworkConfigLib.get_usdc_contract_address();
        ethContractAddress = NetworkConfigLib.get_usdc_contract_address();

        transaction = new Transaction (usdcContractAddress, ethContractAddress);

        address txAddress = address (transaction);
        
        treasury = new Treasury (i_owner, address (txAddress));
        
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

    function transfer_funds_from_external(
        IERC20 _token,
        string memory _tokenName,
        address _from,
        string memory _fromName,
        address _to,
        string memory _toName,
        uint256 _amount
    ) internal {
        uint256 balanceOfSenderBeforeTransfer = _token.balanceOf(_from);
        if (balanceOfSenderBeforeTransfer < _amount) {
            revert DoesNotHaveEnoughUSDC (_from,_fromName,_to, _toName,  _amount);
        }
        if (_token.allowance(msg.sender, address(this)) < _amount){
            revert DoesNotHaveEnoughAllowance (_from, _fromName, address(this), ILENDSTR, _amount);
        }

        uint256 balanceOfReceiverBeforeReceive = _token.balanceOf(_to);

        if (_token.transferFrom(_from,_to, _amount) == false) {
            revert TransferFromFailed(_tokenName,
                _from,
                _fromName,
                _to,
                _toName,
                _amount
            );
        }

          
        uint256 newBalance = _token.balanceOf(_to);

        if (newBalance < _amount + balanceOfSenderBeforeTransfer) {
            revert BalanceMismatchAfterIncomingTransfer(
                _tokenName,
                _from,
                _fromName,
                _to,
                _toName,
                _amount,
                balanceOfSenderBeforeTransfer,
                newBalance
            );
        }
    }

    function deposit_funds (uint256 _amount, uint256 _lockupPeriod) external {
        transfer_funds_from_external(
            IERC20(usdcContractAddress),
            USDCSTR,
            msg.sender,
            DEPOSITORSTR,
            address(deposit),
            DEPOSITCONTRACTSTR,
            _amount
        );
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


   function deposit_collateral_borrow (uint256 _amount) 
    external {
        
        transfer_funds_from_external(
            IERC20(usdcContractAddress),
            ETHSTR,
            msg.sender,
            COLLATERALPROVIDERSTR,
            address(deposit),
            COLLATERALCONTRACTSTR,
            _amount
        );

        collateral.update_collateral_records (msg.sender, _amount);


        emit CollateralDepositDone(
            msg.sender,
            address(collateral),
            _amount,
            block.timestamp
        );
        

        if (!borrow.borrower_exists (msg.sender))
            borrow.add_new_borrower (msg.sender, 0, 0, 0, 0);
        uint256 collateralDepositCount = collateral.get_collateral_deposit_count(msg.sender);
        uint256 borrowAmount = borrow.update_borrow_records (msg.sender, collateralDepositCount-1);
        collateral.update_borrowed_against_collateral (msg.sender, collateralDepositCount-1, true);
        
        IERC20 token = IERC20 (usdcContractAddress);
        uint256 currentBalance = token.balanceOf(address (deposit));
        deposit.withdraw_to_borrower (token, msg.sender, borrowAmount, msg.sender, collateralDepositCount-1);
        uint256 newBalance = token.balanceOf(address(deposit));
        if (newBalance > currentBalance - borrowAmount) {
            revert TransferAmountMismatchInDepositPoolAfterOutgingTransfer_Borrower(
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

    /**
     * @notice Allows a borrower to close an active loan by repaying the owed amount in ETH.
     * @dev 
     * - Forwards the received ETH to the `payback` contract to process repayment.
     * - After successful repayment, instructs the `collateral` contract to unlock the borrower's collateral.
     * - Caller must send the exact repayment amount as `msg.value`.
     * 
     * @param _loanID The ID of the loan the caller wants to close.
     */
    function close_loan (uint256 _loanID, uint256 _amount) external {
        RepaymentComponent memory rep = payback.process_repayment (msg.sender, _loanID, _amount);
        transfer_funds_from_external(
            IERC20(usdcContractAddress),
            USDCSTR,
            msg.sender,
            BORROERCONTRACTSTR,
            address(deposit),
            DEPOSITCONTRACTSTR,
            rep.pAmount + rep.iAmount
        );

        transfer_funds_from_external(
            IERC20(usdcContractAddress),
            USDCSTR,
            msg.sender,
            BORROERCONTRACTSTR,
            address(treasury),
            TREASURYCONTRACTSTR,
            rep.rAmount
        );

        collateral.unlock_collateral (IERC20 (ethContractAddress), msg.sender, _loanID);
    }

    /**
     * @notice Retrieves all liquidation-ready collateral records grouped by borrower.
     * @dev 
     * - Fetches a list of borrower addresses with at least one liquidation-ready position.
     * - For each borrower, calls the registry to get their associated liquidation-ready collaterals.
     * - Returns a two-dimensional array where each inner array contains the collaterals for a borrower.
     * 
     * @return An array of arrays, where each inner array holds `LiquidationReadyCollateral` entries for a borrower.
     */
    function get_liquidation_ready_collaterals () 
    external 
    view 
    returns (LiquidationReadyCollateral [] [] memory) {
        address [] memory list = liquidationRegistry.get_liqudation_ready_addresses (); 
        uint256 n = list.length;
        LiquidationReadyCollateral [][] memory _cols = new LiquidationReadyCollateral [][] (n);
        for (uint256 i=0; i< n; i++){
            _cols [i] = liquidationRegistry.get_liquidation_ready_collaterals_by_borrower (list [i]);
        }
        return _cols;
    }

        /**
     * @notice Allows a third-party liquidator to liquidate a borrower's USDC loan in exchange for ETH collateral.
     * @dev 
     * - This function performs multiple checks:
     *   - Ensures the liquidator has sufficient USDC balance and allowance.
     *   - Transfers USDC to the Deposit contract and validates balance updates.
     *   - Calls the liquidation engine to process the liquidation.
     *   - Transfers ETH collateral from the Collateral contract to the liquidator.
     *   - Emits events to record the liquidation and ETH transfer.
     * - The function uses custom errors to save gas and provide precise reverts.
     * - Emits `LiquidationUSDCReceived` and `LiquidatorReceivesETH` on success.
     * 
     * @param _borrower The address of the borrower whose position is being liquidated.
     * @param _loanID The ID of the loan associated with the borrower's position.
     * @param _usdcAmount The amount of USDC the liquidator is using to repay the borrower's debt.
     */

    function liquidate_position_for_ETH 
    (
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount
    ) 
    external {
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
            revert TransferAmountMismatchInDepositPoolAfterIncomingTransfer_Liquidation(
                _usdcAmount,
                currentBalance,
                newBalance
            );
        }

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

        emit LiquidationUSDCReceived(
            msg.sender,
            _usdcAmount,
            currentBalance + _usdcAmount,
            block.timestamp
        );
        emit LiquidatorReceivesETH(
            msg.sender,
            ethAmount,
            newBalance,
            block.timestamp
        );

    }
}