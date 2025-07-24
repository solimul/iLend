//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Borrow} from "../borrow/Borrow.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {RepaymentComponent, BorrowRecord, Lender, DepositRecord, InterestEarned} from "../shared/SharedStructures.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Payback {
    
    error BorrowerDoesNotExist(address borrowerAddress);
    error RemainingAmountNotZeroAfterRepayment(
        address borrowerAddress, 
        uint256 loanID, 
        uint256 amount, 
        uint256 principalAmount, 
        uint256 interestAmount, 
        uint256 protocolRewardAmount, 
        uint256 remaining
    );
    error NotAllInterestPaymentSuccessful(
        address borrowerAddress, 
        uint256 loanID, 
        uint256 interestAmount, 
        uint256 principalAmount, 
        uint256 remaining
    );

    Borrow immutable private iBorrow;
    Deposit immutable private iDeposit;
    Treasury immutable private iTreasury;
    IERC20 immutable private iUSDC;

    


    constructor 
    (
        address _bAddress, 
        address _dAddress, 
        address _tAddress, 
        address _usdc
    ) 
             {
        iBorrow = Borrow (_bAddress);
        iDeposit = Deposit (_dAddress);       
        iTreasury = Treasury (payable (_tAddress));
        iUSDC = IERC20 (_usdc);
    }

    modifier only_existing_borrower
    (
        address _borrowerAddress
    ) {
        if (iBorrow.borrower_exists(_borrowerAddress) == false) {
            revert BorrowerDoesNotExist(_borrowerAddress);
        }
        _;
    }


    function update_principal_records 
    (
        address _depositorAddress, 
        uint256 _id
    ) 
    public 
    returns (uint256) {
        uint256 lentOutAmount = iDeposit.get_lentout_amount (_depositorAddress, _id);
        uint256 old = iDeposit.get_usdc_balance();
        require (old >= lentOutAmount, "Borrower does not have enough USDC for principal repayment.");        
        iDeposit.update_principal_payback_record (
              _depositorAddress, _id);
        return lentOutAmount;
    }

    function update_principal_receipt 
    (
        address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _principalAmount
    ) 
    internal {
        BorrowRecord memory bRecord = iBorrow.get_borrow_record (_borrowersAddress, _loanID);
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
    internal 
    returns (uint256) {
        uint256 lentFromThisDepositAccount = iDeposit.get_lentout_amount (_lender, _depositID);
        uint256 old = iDeposit.get_usdc_balance();
        require (old >= lentFromThisDepositAccount, "Borrower does not have enough USDC for interest repayment.");        
        
        uint256 interestPaid = 
                iDeposit.update_interest_payback_record (
                    _borrower, _loanID, _lender, _depositID, 
                    _interestAmount, _principalAmount, lentFromThisDepositAccount
                );
        return interestPaid;
    }

    function update_interest_receipt  
    (
        address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _interestAmount, 
        uint256 _principalAmount
    ) 
    internal  { 
        BorrowRecord memory bRecord = iBorrow.get_borrow_record (_borrowersAddress, _loanID);
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
        if (remaining != 0) {
            revert NotAllInterestPaymentSuccessful(
                _borrowersAddress, 
                _loanID, 
                _interestAmount, 
                _principalAmount, 
                remaining
            );
        }
    }

    function update_protocol_reward_receipt 
    (
        address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _amount
    ) 
    internal {
        iTreasury.update_protocol_reward_records (_amount, _borrowersAddress, _loanID);
    }

    function update_loan_repayment 
    (
        address _borrowersAddress, 
        uint256 loanID, 
        uint256 amount
    ) 
    external 
    only_existing_borrower(_borrowersAddress)
    returns (RepaymentComponent memory) {
        RepaymentComponent memory rep = iBorrow.calculate_repayment_components (_borrowersAddress, loanID);
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

