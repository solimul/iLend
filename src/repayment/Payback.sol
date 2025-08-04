//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Borrow} from "../borrow/Borrow.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {RepaymentComponent, BorrowRecord, Lender, DepositRecord, InterestEarned} from "../shared/SharedStructures.sol";

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {iLend} from "../ILend.sol";

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

    error NotAllPrincipalPaymentSuccessful(
        address borrowerAddress, 
        uint256 loanID, 
        uint256 principalAmount, 
        uint256 remaining
    );
    error NotEnoughAmountForRepayment(
        address borrowerAddress, 
        uint256 loanID, 
        uint256 amount, 
        uint256 principalAmount, 
        uint256 interestAmount, 
        uint256 protocolRewardAmount, 
        uint256 requiredAmount
    );
    error BorrowerDoesNotHaveEnoughUSDCForPrincipalRepayment(
        address borrowerAddress, 
        uint256 lentOutAmount, 
        uint256 oldBalance
    );
    error BorrowerDoesNotHaveEnoughUSDCForInterestRepayment(
        address borrowerAddress, 
        uint256 loanID, 
        address lender, 
        uint256 depositID, 
        uint256 interestAmount, 
        uint256 principalAmount, 
        uint256 oldBalance
    );

    error OnlyOwnerCanAccessThisFunction (address sender, address owner);
    error OnlyILendContractCanAccessThisFunction (address sender, address owner);

    Borrow immutable private iBorrow;
    Deposit immutable private iDeposit;
    Treasury immutable private iTreasury;
    IERC20 immutable private iUSDC;

   address private facadeContractAddress;
   address private immutable iOwnerAddress;

    modifier only_owner_contract (address _sender) {
        if (_sender != iOwnerAddress) {
            revert OnlyOwnerCanAccessThisFunction (_sender, iOwnerAddress);
        }
        _;
    }

    modifier only_facade_contract(address _sender) {
        if (_sender != facadeContractAddress) {
            revert OnlyILendContractCanAccessThisFunction (_sender, facadeContractAddress);
        }
        _;
    }

    /**
     * @notice Ensures that the provided address belongs to an existing borrower.
     * @dev Checks the existence of a borrower using the `iBorrow` contract. Reverts with 
     * `BorrowerDoesNotExist` if the borrower is not registered.
     * @param _borrowerAddress The address to verify as an existing borrower.
    */


    modifier only_existing_borrower
    (
        address _borrowerAddress
    ) {
        if (iBorrow.borrower_exists(_borrowerAddress) == false) {
            revert BorrowerDoesNotExist(_borrowerAddress);
        }
        _;
    }

    
    /**
     * @notice Initializes the core contract references for borrowing, deposit, treasury, and USDC token.
     * @dev Sets the external contract interfaces using the provided addresses during deployment.
     * @param _bAddress The address of the Borrow contract.
     * @param _dAddress The address of the Deposit (Lender) contract.
     * @param _tAddress The address of the Treasury contract.
     * @param _usdc The address of the USDC ERC20 token contract.
     */


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
        iOwnerAddress = msg.sender;
    }

   

    /**
     * @notice Updates the principal payback record for a specific deposit account.
     * @dev Checks if there is sufficient USDC balance to repay the lent-out amount for the given 
     * deposit account. Then delegates the record update to the `iDeposit` contract and returns the 
     * repaid amount.
     * @param _funderAddress The address of the funder (lender) whose principal is being repaid.
     * @param _id The identifier of the lender’s deposit account.
     * @return lentOutAmount The amount of principal repaid to the specified deposit account.
     */

    function update_principal_records 
    (
        address _funderAddress, 
        uint256 _id
    ) 
    internal 
    returns (uint256) {
        uint256 lentOutAmount = iDeposit.get_lentout_amount (_funderAddress, _id);
        uint256 old = iDeposit.get_usdc_balance();
        if (old < lentOutAmount)
            revert BorrowerDoesNotHaveEnoughUSDCForPrincipalRepayment(_funderAddress, lentOutAmount, old);
        iDeposit.update_principal_payback_record (
              _funderAddress, _id);
        return lentOutAmount;
    }

    /**
         * @notice Distributes the principal portion of a loan repayment among all associated lenders.
         * @dev Retrieves the borrow record and iterates over each lender and their deposit accounts to 
         * update the principal repayment records. Accumulates the total repaid amount and reverts if 
         * there is any mismatch between the intended and actual repayment.
         * @param _borrowersAddress The address of the borrower repaying the principal.
         * @param _loanID The unique identifier of the loan whose principal is being repaid.
         * @param _principalAmount The total principal amount to be repaid and distributed to lenders.
     */

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
        if (remaining != 0)
            revert NotAllPrincipalPaymentSuccessful(
                _borrowersAddress, 
                _loanID, 
                _principalAmount, 
                remaining
            );
        }

        /**
         * @notice Updates the interest payback record for a specific lender’s deposit account.
         * @dev Verifies that the contract has enough USDC to cover the interest repayment for this 
         * deposit account. Delegates the actual update to the `iDeposit` contract and returns 
         * the interest paid for this lender and deposit ID.
         * @param _borrower The address of the borrower repaying the interest.
         * @param _loanID The unique identifier of the loan associated with the repayment.
         * @param _lender The address of the lender receiving the interest.
         * @param _depositID The identifier of the lender's deposit account involved in the loan.
         * @param _interestAmount The total interest amount intended to be paid across all lenders.
         * @param _principalAmount The total principal of the loan, used to compute proportional interest.
         * @return interestPaid The actual interest amount paid to this lender for the given deposit account.
     */


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
        if (old < lentFromThisDepositAccount)
            revert BorrowerDoesNotHaveEnoughUSDCForInterestRepayment(_borrower, _loanID, _lender, _depositID, _interestAmount, _principalAmount, old);
        
        uint256 interestPaid = 
                iDeposit.update_interest_payback_record (
                    _borrower, _loanID, _lender, _depositID, 
                    _interestAmount, _principalAmount, lentFromThisDepositAccount
                );
        return interestPaid;
    }

    /**
     * @notice Distributes the interest portion of a loan repayment among all associated lenders.
     * @dev Retrieves the borrow record and iterates through each lender and their deposit accounts
     * to update their interest records. Accumulates distributed interest and reverts if any amount 
     * remains undistributed.
     * @param _borrowersAddress The address of the borrower making the interest repayment.
     * @param _loanID The unique identifier of the loan for which interest is being repaid.
     * @param _interestAmount The total interest amount to be distributed to lenders.
     * @param _principalAmount The principal amount used to proportionally calculate each lender’s interest.
     */

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

    /**
     * @notice Updates the protocol reward records for a specific loan repayment.
     * @dev Internally calls the `iTreasury` contract to record the protocol reward amount 
     * associated with the given borrower and loan ID.
     * @param _borrowersAddress The address of the borrower making the repayment.
     * @param _loanID The unique identifier of the loan associated with the reward.
     * @param _amount The amount of protocol reward to be recorded.
     */

    function update_protocol_reward_receipt 
    (
        address _borrowersAddress, 
        uint256 _loanID, 
        uint256 _amount
    ) 
    internal {
        iTreasury.update_protocol_reward_records (_amount, _borrowersAddress, _loanID);
    }

    /**
         * @notice Updates the repayment of a loan by distributing the provided amount into 
         * principal, interest, and protocol reward components. Reverts if any excess amount remains 
         * after repayment.
         * @dev This function retrieves the repayment breakdown from `iBorrow`, and sequentially updates
         * interest, protocol reward, and principal records. It expects an exact amount; any overpayment 
         * will trigger a revert with detailed information.
         * @param _borrowersAddress The address of the borrower repaying the loan.
         * @param loanID The unique identifier of the loan to be repaid.
         * @param amount The total repayment amount provided by the borrower. Must match the sum of 
         * principal, interest, and protocol reward.
         * @return rep A `RepaymentComponent` struct detailing the breakdown of the repaid amount.
     */

    function update_loan_repayment 
    (
        address _borrowersAddress, 
        uint256 loanID, 
        uint256 amount
    ) 
    external 
    only_facade_contract (msg.sender)
    only_existing_borrower(_borrowersAddress)
    returns (RepaymentComponent memory) {
        RepaymentComponent memory rep = iBorrow.calculate_repayment_components (_borrowersAddress, loanID);
        uint256 requiredAmount = rep.pAmount + rep.iAmount + rep.rAmount;
        uint256 remaining = amount;
        if (amount < requiredAmount) {
            revert NotEnoughAmountForRepayment(
                _borrowersAddress, 
                loanID, 
                amount, 
                rep.pAmount, 
                rep.iAmount, 
                rep.rAmount, 
                requiredAmount
            );
        }        
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

    function register_caller_contracts 
    (
        address _iLendAddress
    ) 
    external
    only_owner_contract (msg.sender) {
        facadeContractAddress = _iLendAddress;
    }
}

