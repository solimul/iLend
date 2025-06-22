//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Borrow} from "./Borrow.sol";
import {Deposit} from "./Deposit.sol";
import {Treasury} from "./Treasury.sol";

import {RepaymentComponent, BorrowRecord, Lender} from "./shared/SharedStructures.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Repayment {
    Borrow private borrow;
    Deposit private deposit;
    Treasury private treasury;
    IERC20 private usdc;


    constructor (address _bAddress, address _dAddress, address _tAddress, address _usdc) {
        borrow = Borrow (_bAddress);
        deposit = Deposit (_dAddress);       
        treasury = Treasury (payable (_tAddress));
        usdc = IERC20 (_usdc);
    }

    modifier only_existing_borrower(address _borrowerAddress) {
        require(borrow.borrower_exists(_borrowerAddress), "Borrower does not exist");
        _;
    }

    function pay_loan_principal 
    (address _borrowersAddress, 
    uint256 _loanID, 
    uint256 _principalAmount) internal {
        BorrowRecord memory bRecord = borrow.get_borrow_record (_borrowersAddress, _loanID);
        uint256 remaining = _principalAmount;
        for (uint256 i=0; i< bRecord.lenders.length; i++) {
            address lAddress = bRecord.lenders [i].lender;
            uint256 borrowedFromThisLender = 0;
            for (uint256 j=0; j<bRecord.lenders [i].depositAccountIDs.length; j++){
                uint256 id = bRecord.lenders [i].depositAccountIDs [j];
                borrowedFromThisLender += deposit.add_repaid_principal (_borrowersAddress, lAddress, id);
            }
            remaining -= borrowedFromThisLender;
        }
        require (remaining == 0, "not all pricipal repayment transferred");
    }


    function pay_interest_deposit(
    address borrower,
    uint256 loanID,
    address lender,
    uint256 depositID,
    uint256 interestAmount,
    uint256 principalAmount
    ) internal returns (uint256) {
        return deposit.add_interest_for_lender (
            borrower, loanID, lender, depositID, interestAmount, principalAmount
        );
    }

    function pay_interest  (address _borrowersAddress, uint256 _loanID, uint256 _interestAmount, uint256 _principalAmount) 
    internal  { 
        BorrowRecord memory bRecord = borrow.get_borrow_record (_borrowersAddress, _loanID);
        uint256 remaining = _interestAmount;
        uint256 interestToThisLender = 0;
        for (uint256 i=0;i< bRecord.lenders.length; i++){
            Lender memory _lender = bRecord.lenders [i]; 
            address lAddress = _lender.lender; 
            for (uint256 j=0; j < _lender.depositAccountIDs.length; j++){
                uint256 depositID = _lender.depositAccountIDs [j];
                interestToThisLender += pay_interest_deposit (
                    _borrowersAddress, _loanID, lAddress, depositID, _interestAmount, _principalAmount);
            }
            remaining -= interestToThisLender;
        }
        require (remaining == 0, "not all interest payment was successful");

    }

    function pay_protocol_reward (address _borrowersAddress, uint256 loanID, uint256 amount) 
    internal {
        treasury.reciveERC20Deposit (usdc, _borrowersAddress, amount);
        treasury.updateProtocolRewardRecord (amount, _borrowersAddress, loanID);
    }

    function pay_remaining_to_treasury (address _borrowersAddress, uint256 amount, string memory context) 
    internal {
        treasury.reciveERC20Deposit (usdc, _borrowersAddress, amount);
        treasury.updateMiscRecievedRecord (amount, context);
    }

    function process_repayment (address _borrowersAddress, uint256 loanID, uint256 amount) 
    external 
    only_existing_borrower(_borrowersAddress){
        RepaymentComponent memory rep = borrow.calculate_repayment_components (_borrowersAddress, loanID);
        uint256 requiredAmount = rep.pAmount + rep.iAmount + rep.rAmount;
        uint256 remaining = amount;
        require(amount >= requiredAmount, "Amount is not Enough");
        
        //pay interests
        pay_interest (_borrowersAddress, loanID, rep.iAmount, rep.pAmount);
        remaining -= rep.iAmount;

        //pay protocol reward
        pay_protocol_reward (_borrowersAddress, loanID, rep.rAmount);
        remaining -= rep.rAmount;
        //repay principal
        pay_loan_principal (_borrowersAddress, loanID, rep.pAmount);
        remaining -= rep.pAmount;

        if (remaining > 0) 
            pay_remaining_to_treasury (_borrowersAddress, amount, "");
    }
}