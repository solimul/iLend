//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Borrow} from "../borrow/Borrow.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {Transaction} from "../misc/Transcation.sol";

import {RepaymentComponent, BorrowRecord, Lender, DepositRecord, InterestEarned} from "../shared/SharedStructures.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Payback {
    
    Borrow private borrow;
    Deposit private deposit;
    Treasury private treasury;
    Transaction private transaction;
    IERC20 private usdc;

    error RemainingAmountNotZeroAfterRepayment(
        address borrowerAddress, 
        uint256 loanID, 
        uint256 amount, 
        uint256 principalAmount, 
        uint256 interestAmount, 
        uint256 protocolRewardAmount, 
        uint256 remaining
    );


    constructor (address _bAddress, 
            address _dAddress, 
            address _tAddress, 
            address _usdc, 
            address _tranAddress) {
        borrow = Borrow (_bAddress);
        deposit = Deposit (_dAddress);       
        treasury = Treasury (payable (_tAddress));
        usdc = IERC20 (_usdc);
        transaction = Transaction (_tranAddress);
    }

    modifier only_existing_borrower(address _borrowerAddress) {
        require(borrow.borrower_exists(_borrowerAddress), "Borrower does not exist");
        _;
    }


    function update_principal_records 
    (
        address _depositorAddress, 
        uint256 _id
    ) 
    public 
    returns (uint256) {
        uint256 lentOutAmount = deposit.get_lentout_amount (_depositorAddress, _id);
        uint256 old = deposit.get_usdc_balance();
        require (old >= lentOutAmount, "Borrower does not have enough USDC for principal repayment.");        
        deposit.update_principal_payback_record (
              _depositorAddress, _id);
        // require (transaction.check_approval_and_safe_transfer("USDC",_borrowerAddress, address (deposit), lentOutAmount), 
        //             "Cannot receive from the Borrower");
        // uint256 current = deposit.get_usdc_balance();
        //require (current == old + lentOutAmount, "USDC transfer amount mismatch");
        return lentOutAmount;
    }

    function update_principal_receipt (address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _principalAmount) 
    internal {
        BorrowRecord memory bRecord = borrow.get_borrow_record (_borrowersAddress, _loanID);
        uint256 remaining = _principalAmount;
        for (uint256 i=0; i< bRecord.lenders.length; i++) {
            address lAddress = bRecord.lenders [i].lender;
            uint256 borrowedFromThisLender = 0;
            for (uint256 j=0; j<bRecord.lenders [i].depositAccountIDs.length; j++){
                uint256 id = bRecord.lenders [i].depositAccountIDs [j];
                borrowedFromThisLender += update_principal_records (lAddress, id);
            }
            remaining -= borrowedFromThisLender;
        }
        require (remaining == 0, "not all pricipal repayment transferred");
    }


    function update_interest_record
        (
            address _borrower,
            uint256 _loanID,
            address _lender,
            uint256 _depositID,
            uint256 _interestAmount,
            uint256 _principalAmount
        ) 
    internal returns (uint256) {
        uint256 lentFromThisDepositAccount = deposit.get_lentout_amount (_lender, _depositID);
        uint256 old = deposit.get_usdc_balance();
        require (old >= lentFromThisDepositAccount, "Borrower does not have enough USDC for interest repayment.");        
        
        uint256 interestPaid = 
                deposit.update_interest_payback_record (
                    _borrower, _loanID, _lender, _depositID, 
                    _interestAmount, _principalAmount, lentFromThisDepositAccount
                );

        // require (transaction.check_approval_and_safe_transfer("USDC",_borrower, address (deposit), interestPaid), 
        //             "Cannot receive Interest for this deposit record from the Borrower");
        
        // uint256 current = deposit.get_usdc_balance();
        // require (current == old + interestPaid, "USDC transfer amount mismatch");
        return interestPaid;
    }

    function update_interest_receipt  (address _borrowersAddress, 
                           uint256 _loanID, 
                           uint256 _interestAmount, 
                           uint256 _principalAmount) 
    internal  { 
        BorrowRecord memory bRecord = borrow.get_borrow_record (_borrowersAddress, _loanID);
        uint256 remaining = _interestAmount;
        uint256 interestToThisLender = 0;
        for (uint256 i=0;i< bRecord.lenders.length; i++){
            Lender memory _lender = bRecord.lenders [i]; 
            address lAddress = _lender.lender; 
            for (uint256 j=0; j < _lender.depositAccountIDs.length; j++){
                uint256 depositID = _lender.depositAccountIDs [j];
                interestToThisLender += update_interest_record (
                    _borrowersAddress, _loanID, lAddress, depositID, _interestAmount, _principalAmount);
            }
            remaining -= interestToThisLender;
        }
        require (remaining == 0, "not all interest payment was successful");

    }

    function update_protocol_reward_receipt 
    (
        address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _amount
    ) 
    internal {
        treasury.update_protocol_reward_record (_amount, _borrowersAddress, _loanID);
    }

    // function pay_remaining_to_treasury (address _borrowersAddress, 
    //                                     uint256 amount, 
    //                                     string memory context) 
    // internal {
    //     treasury.reciveERC20Deposit (usdc, _borrowersAddress, amount);
    //     treasury.updateMiscRecievedRecord (amount, context);
    // }

    function update_loan_repayment 
    (
        address _borrowersAddress, 
        uint256 loanID, 
        uint256 amount
    ) 
    external 
    only_existing_borrower(_borrowersAddress)
    returns (RepaymentComponent memory) {
        RepaymentComponent memory rep = borrow.calculate_repayment_components (_borrowersAddress, loanID);
        uint256 requiredAmount = rep.pAmount + rep.iAmount + rep.rAmount;
        uint256 remaining = amount;
        require(amount >= requiredAmount, "Amount is not Enough");
        
        //pay interests
        update_interest_receipt (_borrowersAddress, loanID, rep.iAmount, rep.pAmount);
        remaining -= rep.iAmount;

        //pay protocol reward
        update_protocol_reward_receipt (_borrowersAddress, loanID, rep.rAmount);
        remaining -= rep.rAmount;
        //repay principal
        update_principal_receipt (_borrowersAddress, loanID, rep.pAmount);
        remaining -= rep.pAmount;

        if (remaining > 0){
            revert RemainingAmountNotZeroAfterRepayment(
                _borrowersAddress, 
                loanID, 
                amount, 
                rep.pAmount, 
                rep.iAmount, 
                rep.rAmount, 
                remaining
            );
        }
        return rep;
    }
}

