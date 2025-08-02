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
import {Monitor} from "./liquidation/Monitor.sol";
import {LiquidationRegistry} from "./liquidation/LiquidationRegistry.sol";
import {LiquidationEngine} from "./liquidation/LiquidationEngine.sol";

import {RevertLib} from "./lib/RevertLib.sol";



import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
 
import {console} from "../lib/forge-std/src/Script.sol";

contract iLend {

    using RevertLib for bytes;

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

    event SentETHToLiquidator(
        address indexed liquidator,
        uint256 ethAmount,
        uint256 poolBalance,
        uint256 timestamp
    );

    error DoesNotHaveEnoughUSDCWhileDepositing ();
    error DoesNotHaveEnoughUSDCAllowanceWhileDepositing ( );
    error TransferFromFailedWhileDepositingUSDC();
    error BalanceMismatchAfterIncomingTransferWhileDepositingUSDC ();

    error DoesNotHaveEnoughETHWhileDepositingCollateral ();
    error DoesNotHaveEnoughETHAllowanceWhileDepositingCollateral ();
    error TransferFromFailedWhileDepositingCollateral();
    error BalanceMismatchAfterIncomingTransferWhileDepositingCollateral ();

    error DoesNotHaveEnoughUSDCWhileRepayingPrincipal ();
    error DoesNotHaveEnoughUSDCAllowanceWhileRepayingPrincipal ();
    error TransferFromFailedWhileRepayingPrincipal();
    error BalanceMismatchAfterIncomingTransferWhileRepayingPrincipal ();

    error DoesNotHaveEnoughUSDCWhileRepayingInterest ();
    error DoesNotHaveEnoughUSDCAllowanceWhileRepayingInterest ();
    error TransferFromFailedWhileRepayingInterest();
    error BalanceMismatchAfterIncomingTransferWhileRepayingInterest ();

    error DoesNotHaveEnoughUSDCWhilePayingProtocolReward ();
    error DoesNotHaveEnoughUSDCAllowanceWhilePayingProtocolReward ();
    error TransferFromFailedWhilePayingProtocolReward();
    error BalanceMismatchAfterIncomingTransferWhilePayingProtocolReward ();

    error BalanceMismatchAfterOutgingTransferWhilBorrowingUSDC ();
    error BalanceMismatchAfterOutgoingETHTransferToLiquidator ();

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

    error OnlyOwnerCanCallThisFunction(address caller, address iOwner);
    error TransferAmountMismatchInDepositPoolAfterIncomingTransfer_Liquidation(
        uint256 amountSent,
        uint256 beforeTransferBalance,
        uint256 newBalance
    );

    error ExternalAccessNotAllowed ();


    Params immutable private iParams;   
    address immutable private iOwner;
    Deposit immutable private iDeposit;
    Collateral immutable private iCollateral;
    Borrow immutable private iBorrow;
    Treasury immutable private iTreasury;
    Payback immutable private iPayback;
    Monitor immutable private iMonitor;
    AggregatorV3Interface immutable private iPriceFeed;
    LiquidationRegistry private iLiquidationRegistry;
    LiquidationEngine private iLiquidationEngine;

    address private iUSDCContractAddress;
    address private iETHContractAddress;

    uint256 private constant HUNDRED = 100;

    bool private sTesting = true;
    
    // Modifiers
    modifier only_owner() {
        if (msg.sender != iOwner) {
            revert OnlyOwnerCanCallThisFunction(msg.sender, iOwner);
        }
        _;
    }


    /**
     * @notice Initializes the iLend router with addresses of pre-deployed modules.
     * @notice This constructor follows factory pattern, where all components are already deployed. 
     *  Take the Borrow Contract as an example. Factory pattern allows you to:
          - Decoupling: The factory deploys BorrowV2 (or any variant) separately 
                    and passes its address into iLend, so you never modify the iLend code.

          - Swappability: You can seamlessly swap in different Borrow implementations by updating 
                        only the factory’s deployment script.

          - Testability: Inject stub or malicious Borrow contracts for integration tests 
                without touching the iLend facade.

          - Stability: Keeps the iLend router contract unchanged and audit‑stable, 
                    since wiring happens externally.

          - Upgrade Safety: Enables hot‑fixes, A/B testing, and rollbacks of Borrow logic 
                    without redeploying or renaming inside iLend.
     * @dev 
     * - This constructor does not deploy any components.
     * - It wires together the already-deployed modules of the lending protocol.
     * - Sets the protocol owner as the caller (`msg.sender`).
     * - Assigns references to the configuration, tokens, core contracts, and supporting modules.
     * - Links the `LiquidationEngine` with the `Collateral` contract via a setup call.
     * 
     * @param _params Address of the Params configuration contract.
     * @param _priceFeed Address of the Chainlink price feed.
     * @param _usdcContractAddress Address of the USDC ERC20 token contract.
     * @param _ethContractAddress Address of the wrapped ETH (WETH) ERC20 token contract.
     * @param _treasury Address of the Treasury contract (payable).
     * @param _collateral Address of the Collateral management contract.
     * @param _deposit Address of the Deposit contract.
     * @param _borrow Address of the Borrow logic contract.
     * @param _payback Address of the Payback (repayment) contract.
     * @param _liquidationRegistry Address of the LiquidationRegistry module.
     * @param _monitor Address of the liquidation Monitor contract.
     * @param _liquidationEngine Address of the LiquidationEngine contract.
     */

    constructor
    (
        address _params,
        address _priceFeed,
        address _usdcContractAddress,
        address _ethContractAddress,
        address _treasury,
        address _collateral,
        address _deposit,
        address _borrow,
        address _payback,
        address _liquidationRegistry,
        address _monitor,
        address _liquidationEngine,
        bool testing
    ) {
        iOwner                = msg.sender;

        iParams               = Params(_params);
        iPriceFeed              = AggregatorV3Interface(_priceFeed);

        iUSDCContractAddress    = _usdcContractAddress;
        iETHContractAddress     = _ethContractAddress;

        // Core modules
        iTreasury               = Treasury(payable (_treasury));
        iCollateral             = Collateral(_collateral);
        iDeposit                = Deposit(_deposit);
        iBorrow                 = Borrow(_borrow);
        iPayback                = Payback(_payback);
        iLiquidationRegistry    = LiquidationRegistry(_liquidationRegistry);
        iMonitor                = Monitor(_monitor);
        iLiquidationEngine      = LiquidationEngine(_liquidationEngine);

        iCollateral.set_liquidation_engine(_liquidationEngine);
        sTesting = testing;
    }    


    /**
     * @notice Transfers ERC20 tokens from an external account to a target contract, with full validation.
     * @dev 
     * - Verifies that the sender has sufficient balance and allowance.
     * - Executes `transferFrom` to move tokens from `_from` to `_to`.
     * - Validates post-transfer balance to ensure expected amount was received.
     * - Reverts with detailed custom errors if any check fails.
     * 
     * @param _token The ERC20 token to transfer.
     * @param _from The address from which funds will be transferred.
     * @param _to The address receiving the funds.
     * @param _amount The amount of tokens to transfer.
     */



    function transfer_funds_from_external(
        IERC20 _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes4 _notEnoughFundsSenderSelector,
        bytes4 _insufficientAllowanceSelector,
        bytes4 _transferFromFailedSelector,
        bytes4 _blananceMismatchSelector
    ) internal {
        uint256 balanceOfSenderBeforeTransfer = _token.balanceOf(_from);
        if (balanceOfSenderBeforeTransfer < _amount) {
            abi.encodeWithSelector(_notEnoughFundsSenderSelector).dynamic_revert();
        }
        if (_token.allowance(msg.sender, address(this)) < _amount){
            abi.encodeWithSelector(_insufficientAllowanceSelector).dynamic_revert();
        }

        uint256 balanceOfReceiverBeforeReceive = _token.balanceOf(_to);

        if (_token.transferFrom(_from,_to, _amount) == false) {
            abi.encodeWithSelector(_transferFromFailedSelector).dynamic_revert();
        }

        uint256 newBalance = _token.balanceOf(_to);
        if (newBalance < _amount + balanceOfReceiverBeforeReceive) {
            abi.encodeWithSelector(_blananceMismatchSelector).dynamic_revert ();
        }
    }

    /**
     * @notice Allows a user to Deposit USDC into the iDeposit contract with a specified lockup period.
     * @dev 
     * - Transfers USDC from the caller to the `Deposit` contract using `transfer_funds_from_external`.
     * - Updates the depositor's state in the `Deposit` contract, including amount and lockup duration.
     * - Emits `FundDepoistDone` to log the Deposit event.
     * 
     * @param _amount The amount of USDC to Deposit.
     * @param _lockupPeriod The duration (in seconds or predefined units) for which the funds will be locked.
     */

    function deposit_my_funds 
    (
        uint256 _amount, 
        uint256 _lockupPeriod
    ) 
    external {
        uint256 fees = (_amount * iParams.get_deposit_fee_parcentage ()) /HUNDRED;
        transfer_funds_from_external(
            IERC20(iUSDCContractAddress),
            msg.sender,
            address(iDeposit),
            _amount- fees,
            DoesNotHaveEnoughUSDCWhileDepositing.selector,
            DoesNotHaveEnoughUSDCAllowanceWhileDepositing.selector,
            TransferFromFailedWhileDepositingUSDC.selector,
            BalanceMismatchAfterIncomingTransferWhileDepositingUSDC.selector
        );
        transfer_funds_from_external(
            IERC20(iUSDCContractAddress),
            msg.sender,
            address(iTreasury),
            fees,
            DoesNotHaveEnoughUSDCWhileDepositing.selector,
            DoesNotHaveEnoughUSDCAllowanceWhileDepositing.selector,
            TransferFromFailedWhileDepositingUSDC.selector,
            BalanceMismatchAfterIncomingTransferWhileDepositingUSDC.selector
        );
        iDeposit.update_post_deposit (msg.sender, _amount, _lockupPeriod);
        iTreasury.update_fees_for_deposit (msg.sender, fees);
        emit FundDepoistDone (
            msg.sender,
            _amount,
            block.timestamp
        );
    } 

    /**
     * @notice Allows a depositor to withdraw a portion or all of their principal Deposit.
     * @dev 
     * - Delegates the withdrawal logic to the `Deposit` contract.
     * - Caller must have sufficient unlocked Deposit balance; otherwise, the withdrawal will revert.
     * 
     * @param amount The amount of deposited principal the caller wishes to withdraw.
     */

    function withdraw_my_deposit 
    (
        uint256 amount
    ) 
    external {
        // Call the withdraw function in the Deposit contract
        iDeposit.withdraw_deposit (msg.sender, amount);
    }

    /**
     * @notice Allows a depositor to withdraw accrued interest from their deposited funds.
     * @dev 
     * - Delegates the withdrawal logic to the `Deposit` contract.
     * - Caller must have sufficient interest accrued; otherwise, the withdrawal will revert.
     * 
     * @param amount The amount of interest the caller wants to withdraw.
     */

    function withdraw_deposited_interest 
    (
        uint256 amount
    ) 
    external {
        // Call the withdraw interest function in the Deposit contract
        iDeposit.withdraw_interest(msg.sender, amount);
    }

    /**
     * @notice Deposits ETH collateral and automatically borrows USDC against it.
     * @dev 
     * - Transfers ETH from the user to the Collateral contract via the Deposit contract.
     * - Updates collateral records and borrower records accordingly.
     * - If the borrower is new, a record is initialized.
     * - Automatically computes the borrowable amount from the latest collateral and transfers USDC from the Deposit contract to the user.
     * - Verifies post-transfer balances to ensure correctness.
     * - Emits `CollateralDepositDone` and `LendingDone` events.
     * 
     * @param _amount The amount of ETH (or wrapped ETH-like token) to Deposit as collateral.
     */


   function _deposit_collateral 
   (
        address _depositor,
        uint256 _amount
   ) 
   internal {    /** while deploying turn it to public */  
        transfer_funds_from_external(
            IERC20(iETHContractAddress),
            _depositor,
            address(iCollateral),
            _amount,
            DoesNotHaveEnoughETHWhileDepositingCollateral.selector,
            DoesNotHaveEnoughETHAllowanceWhileDepositingCollateral.selector,
            TransferFromFailedWhileDepositingCollateral.selector,
            BalanceMismatchAfterIncomingTransferWhileDepositingCollateral.selector);

        iCollateral.update_collateral_records (msg.sender, _amount);

        emit CollateralDepositDone(
            _depositor,
            address(iCollateral),
            _amount,
            block.timestamp
        );
    }

    function deposit_collateral 
    (
        uint256 _amount
    ) external {
        if (sTesting == true)
            _deposit_collateral (msg.sender, _amount);
        else 
            revert ExternalAccessNotAllowed ();
    }

    function borrow_usdc () external returns (uint256 borrowAmount){
        if (sTesting == true)
                borrowAmount = _borrow_usdc (msg.sender);
        else
            revert ExternalAccessNotAllowed ();
    }

    
    function _borrow_usdc (address _borrower) internal returns (uint256) {
        if (!iBorrow.borrower_exists (_borrower))
            iBorrow.add_new_borrower (_borrower, 0, 0, 0, 0);
        uint256 collateralDepositCount = iCollateral.get_collateral_deposit_count(_borrower);
        uint256 borrowAmount = iBorrow.update_borrow_records (_borrower, collateralDepositCount-1);
        iCollateral.update_borrowed_against_collateral (_borrower, collateralDepositCount-1, true);
        IERC20 token = IERC20 (iUSDCContractAddress);
        uint256 currentBalance = token.balanceOf(address (iDeposit));
        iDeposit.withdraw_to_borrower (token, _borrower, borrowAmount, _borrower, collateralDepositCount-1);
        
        uint256 newBalance = token.balanceOf(address(iDeposit));
        if (newBalance > currentBalance - borrowAmount) {
            abi.encodeWithSelector (BalanceMismatchAfterOutgingTransferWhilBorrowingUSDC.selector).dynamic_revert ();
        }
        emit LendingDone(
            _borrower,
            borrowAmount,
            block.timestamp
        );
        return borrowAmount;
    }

    function deposit_collateral_and_borrow(uint256 _amount) 
    external 
    returns (uint256 borrowAmount) {
        _deposit_collateral(msg.sender,_amount);
        borrowAmount = _borrow_usdc(msg.sender);
    }

    /**
     * @notice Returns all collateral positions associated with the caller.
     * @dev 
     * - Sets the borrower contract address in the `collateral` contract before fetching data.
     * - Retrieves an array of `CollateralView` structs representing the caller's collateral state.
     * - Though this function returns data, it is not marked `view` because it modifies state by calling `set_borrower_contract`.
     * 
     * @return An array of `CollateralView` structures describing the caller's collateral positions.
     */

    function get_my_collateral_info () external returns (CollateralView [] memory) {
        // Call the view function in the Collateral contract
        iCollateral.set_borrower_contract(address (iBorrow));
        return iCollateral.get_collateral_depositor_info(msg.sender);
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
    function close_loan 
    (
        uint256 _loanID, 
        uint256 _amount
    ) 
    external {
        RepaymentComponent memory rep = iPayback.update_loan_repayment (msg.sender, _loanID, _amount);
        
        transfer_funds_from_external(
            IERC20(iUSDCContractAddress),
            msg.sender,
            address(iDeposit),
            rep.pAmount,
            DoesNotHaveEnoughUSDCWhileRepayingPrincipal.selector,
            DoesNotHaveEnoughUSDCAllowanceWhileRepayingPrincipal.selector,
            TransferFromFailedWhileRepayingPrincipal.selector,
            BalanceMismatchAfterIncomingTransferWhileRepayingPrincipal.selector
        );

           transfer_funds_from_external(
                IERC20(iUSDCContractAddress),
                msg.sender,
                address(iDeposit),
                rep.iAmount,
                DoesNotHaveEnoughUSDCWhileRepayingInterest.selector,
                DoesNotHaveEnoughUSDCAllowanceWhileRepayingInterest.selector,
                TransferFromFailedWhileRepayingInterest.selector,
                BalanceMismatchAfterIncomingTransferWhileRepayingInterest.selector
            );

        transfer_funds_from_external(
            IERC20(iUSDCContractAddress),
            msg.sender,
            address(iTreasury),
            rep.rAmount,
            DoesNotHaveEnoughUSDCWhilePayingProtocolReward.selector,
            DoesNotHaveEnoughUSDCAllowanceWhilePayingProtocolReward.selector,
            TransferFromFailedWhilePayingProtocolReward.selector,
            BalanceMismatchAfterIncomingTransferWhilePayingProtocolReward.selector
        );

        iCollateral.unlock_collateral (IERC20 (iETHContractAddress), msg.sender, _loanID);
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
        address [] memory list = iLiquidationRegistry.get_liqudation_ready_addresses (); 
        uint256 n = list.length;
        LiquidationReadyCollateral [][] memory _cols = new LiquidationReadyCollateral [][] (n);
        for (uint256 i=0; i< n; i++){
            _cols [i] = iLiquidationRegistry.get_liquidation_ready_collaterals_by_borrower (list [i]);
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
     * - Emits `LiquidationUSDCReceived` and `SentETHToLiquidator` on success.
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
        IERC20 token = IERC20(iUSDCContractAddress);
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
  
        uint256 currentBalance = token.balanceOf (address (iDeposit));

        if (token.transferFrom(msg.sender, address (iDeposit), _usdcAmount) == false) {
            revert LiquidatorUSDCTransferFromFailed(
                msg.sender,
                address(iDeposit),
                _usdcAmount
            );
        }

   

        uint256 newBalance = token.balanceOf (address (iDeposit));

        if (newBalance < currentBalance + _usdcAmount) {
            revert TransferAmountMismatchInDepositPoolAfterIncomingTransfer_Liquidation(
                _usdcAmount,
                currentBalance,
                newBalance
            );
        }

        uint256 ethAmount 
            = iLiquidationEngine.update_on_liquidation_deposit (msg.sender, _borrower, _loanID, _usdcAmount);

        token = IERC20 (iETHContractAddress);
        currentBalance = token.balanceOf(address (iCollateral));

        if (token.balanceOf (address(iCollateral)) < ethAmount) {
            revert CollateralPoolDoesNotHaveEnoughETHForLiquidation(
                address(iCollateral),
                ethAmount,
                token.balanceOf(address(iCollateral))
            );
        }
        iCollateral.withdraw_to_liquidator (token, msg.sender, ethAmount, _borrower, _loanID);
        newBalance = token.balanceOf(address(iCollateral));
        if (newBalance > currentBalance - ethAmount) {
            revert BalanceMismatchAfterOutgoingETHTransferToLiquidator ();
        }

        iLiquidationEngine.set_liquidated_status(_borrower, _loanID, true);

        emit LiquidationUSDCReceived(
            msg.sender,
            _usdcAmount,
            currentBalance + _usdcAmount,
            block.timestamp
        );
        emit SentETHToLiquidator(
            msg.sender,
            ethAmount,
            newBalance,
            block.timestamp
        );
    }
}