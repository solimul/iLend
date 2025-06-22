//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Params} from "./Params.sol";
import {PriceConverter} from "../src/helper/PriceConverter.sol";
import {Deposit} from "./Deposit.sol";
import {Collateral} from "./Collateral.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lender, InterestEarned} from "./shared/SharedStructures.sol";
import {ProtocolReward} from "./ProtocolReward.sol";
import {Treasury} from "./Treasury.sol";
import {RepaymentComponent, BorrowRecord, BorrowerRecord} from "./shared/SharedStructures.sol";

contract Borrower {
    using PriceConverter for uint256;


    event NewBorrowerAdded(
        address indexed borrowerAddress,
        uint256 totalCollateral,
        uint256 totalBorrowed,
        uint256 interestRate,
        uint256 l2b
    );

    event LendingDone(
        address indexed borrowerAddress,
        uint256 indexed correspondingCollateralID,
        uint256 amountLent,
        uint256 totalBorrowed,
        uint256 timestamp
    );

    mapping(address => BorrowerRecord) private borrowers;

    Params private params;
    AggregatorV3Interface private priceFeed;
    Deposit private depositPool;
    Collateral private collateralPool;
    Treasury treasury;
    
    IERC20 private usdcContract;

    modifier onlyExistingBorrower(address _borrowerAddress) {
        require(borrowerExists(_borrowerAddress), "Borrower does not exist");
        _;
    }

    modifier onlyActiveLoan(address _borrowerAddress, uint256 _correspondingColletaralID) {
        require(borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount > 0, "No active loan for this collateral");
        _;
    }

    modifier enoughRepayment (address _borrowerAddress, uint256 _correspondingColletaralID, uint256 _repaymentAmount) {
        require(_repaymentAmount > 0, "Repayment amount must be greater than zero");
        uint256 borrowedAmount = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;
        require(_repaymentAmount <= borrowedAmount, "Repayment amount exceeds borrowed amount");
        uint256 interestRate = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;
        uint256 interestPayable = (borrowedAmount * interestRate * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)) / (365 days * 100);
        require(_repaymentAmount >= interestPayable, "Repayment amount must cover interest payable");
        uint256 protocolReward = (borrowedAmount * params.getReserveFactor() * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)) / (365 days * 100);
        require(_repaymentAmount >= interestPayable + protocolReward, "Repayment amount must cover interest and protocol reward");
        _;
    }

    constructor (Params _params, 
            address _priceFeedAddress, 
            address _depositContractAddress, 
            address _collateralContractAddress,
            address _treasuryContractAddress,
            IERC20 _usdcContract) {
        // Initialize any necessary parameters or state variables
        params = _params;
        depositPool = Deposit (_depositContractAddress);
        collateralPool = Collateral (_collateralContractAddress);
        priceFeed = AggregatorV3Interface (_priceFeedAddress);
        usdcContract = _usdcContract;
        //payable, because Treasury implements fallback
        treasury = Treasury (payable (_treasuryContractAddress));
    }

    function calculateLiquidityToBorrow (address _borrowerAddress) public view onlyExistingBorrower (_borrowerAddress) returns (uint256)  {
        uint256 usdcValue = 0;
        BorrowerRecord storage borrowerRecord = borrowers[_borrowerAddress];
        
        for (uint256 i = 0; i < borrowerRecord.borrowCount; i++) {
            if (!collateralPool.isCollateralAvailableForBorrow(_borrowerAddress, i)){ 
                uint256 collateralL2B = collateralPool.getCollateralL2BByRecord(_borrowerAddress, i);
                uint256 collateralETH = collateralPool.getCollateralETHByRecord (_borrowerAddress, i);
                uint256 collateralETHToUSDC = collateralETH.ethToUSD(priceFeed);
                uint256 adjustedUsdcValue = (collateralETHToUSDC * collateralL2B) / 100;
                usdcValue += adjustedUsdcValue;
            }
        }
        return  usdcValue; // Adjust based on your L2B logic
    }

    function calculateLiquidityToBorrowForCollateral (address _borrowerAddress, uint256 _correspondingColletaralID) public view onlyExistingBorrower (_borrowerAddress) returns (uint256) {
        uint256 collateralL2B = collateralPool.getCollateralL2BByRecord(_borrowerAddress, _correspondingColletaralID);
        uint256 collateralETH = collateralPool.getCollateralETHByRecord (_borrowerAddress, _correspondingColletaralID);
        uint256 collateralETHToUSDC = collateralETH.ethToUSD(priceFeed);
        return (collateralETHToUSDC * collateralL2B) / 100; // Adjust based on your L2B logic
    }

    function borrowerExists(address _borrowerAddress) public view returns (bool) {
        return borrowers[_borrowerAddress].borrowerAddress != address(0);
    }


    function addNewBorrower (
        address _borrowerAddress,
        uint256 _totalCollateral,
        uint256 _totalBorrowed,
        uint256 _interestRate,
        uint256 _l2b
    ) external {
        require (borrowerExists(_borrowerAddress) == false, "Borrower already exists");
        
        BorrowerRecord storage b = borrowers[_borrowerAddress];
        b.borrowerAddress = _borrowerAddress;
        b.totalBorrowed = _totalBorrowed;
        b.borrowCount = 0;

        emit NewBorrowerAdded(
                _borrowerAddress,
                _totalCollateral,
                _totalBorrowed,
                _interestRate,
                _l2b
        );   
    }

    function lendForCollateral (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) external onlyExistingBorrower(_borrowerAddress){
        // the deposit pull must have enough usdc to lend
        uint256 _liquidityToBorrow = calculateLiquidityToBorrowForCollateral (_borrowerAddress, _correspondingColletaralID); 
        
        require (_liquidityToBorrow <= depositPool.getPoolBalance(), "Not enough liquidity in the pool");
        require (collateralPool.isCollateralAvailableForBorrow (_borrowerAddress, _correspondingColletaralID), "Collateral already borrowed against");
        
        Lender [] memory _lenders =  depositPool.lendToBorrower (_borrowerAddress, _liquidityToBorrow);
        BorrowerRecord storage borrower = borrowers[_borrowerAddress];
        borrower.totalBorrowed += _liquidityToBorrow;
        // Create the borrow record without assigning `lenders` yet
        BorrowRecord storage record = borrower.borrows[_correspondingColletaralID];
        record.loanID = _correspondingColletaralID;
        record.amount = _liquidityToBorrow;
        record.borrowTime = block.timestamp;
        record.interestRate = params.getBaseInterestRate();
        record.l2b = collateralPool.getCollateralL2BByRecord(_borrowerAddress, _correspondingColletaralID);
        
        // Manually copy each Lender from _lenders (memory) to record.lenders (storage)
        for (uint256 i = 0; i < _lenders.length; i++) 
            record.lenders.push(_lenders[i]);
        
        
        emit LendingDone(
            _borrowerAddress,
            _correspondingColletaralID,
            _liquidityToBorrow,
            borrower.totalBorrowed,
            block.timestamp
        );
    }

    function getBorrowedAmount (address _borrowerAddress, uint256 _correspondingColletaralID) 
        external 
        view 
        onlyExistingBorrower(_borrowerAddress)         
        returns (uint256) 
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;    
    }

    function getBorrowedInterestRate (address _borrowerAddress, uint256 _correspondingColletaralID) 
        external 
        view 
        onlyExistingBorrower(_borrowerAddress)         
        returns (uint256) 
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;    
    }

    function calculateInterestPayable (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) 
        external 
        view 
        onlyExistingBorrower(_borrowerAddress)         
        returns (uint256) 
    {
        BorrowRecord storage borrowRecord = borrowers[_borrowerAddress].borrows[_correspondingColletaralID];
        uint256 timeElapsed = block.timestamp - borrowRecord.borrowTime;
        uint256 interestPayable = (borrowRecord.amount * borrowRecord.interestRate * timeElapsed) / (365 days * 100);
        return interestPayable;
    }

    function calculateProtocolRewardByReserveFactor (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) 
        external 
        view 
        onlyExistingBorrower(_borrowerAddress)         
        returns (uint256) 
    {
        BorrowRecord storage borrowRecord = borrowers[_borrowerAddress].borrows[_correspondingColletaralID];
        uint256 timeElapsed = block.timestamp - borrowRecord.borrowTime;
        uint256 protocolReward = (borrowRecord.amount * params.getReserveFactor() * timeElapsed) / (365 days * 100);
        return protocolReward;
    }

    function calculate_interest_amount (BorrowerRecord storage _bRecord, BorrowRecord storage r) internal view returns (uint256){
        return (r.interestRate * (_bRecord.totalBorrowed * (block.timestamp -  r.borrowTime))  / (365 days * 100));

    }

    function calculate_protocol_reward  (BorrowerRecord storage _bRecord, BorrowRecord storage r) internal view returns (uint256) {
        return (params.getReserveFactor() *  (_bRecord.totalBorrowed * (block.timestamp -  r.borrowTime))  / (365 days * 100));
    }

    function calculate_repayment_components (address _borrowersAddress, uint256 loanID) internal view returns (RepaymentComponent memory){
        RepaymentComponent memory rep;
        BorrowerRecord storage _bRecord = borrowers [_borrowersAddress];
        BorrowRecord storage r = _bRecord.borrows [loanID];
        rep.pAmount = r.amount;
        rep.iAmount = calculate_interest_amount( _bRecord, r);
        rep.rAmount = calculate_protocol_reward (_bRecord, r);
        return rep;
    }

    function repay_loan_principal (address _borrowersAddress, uint256 loanID, uint256 principalAmount) internal {
        BorrowerRecord storage _bRecord = borrowers [_borrowersAddress];
        BorrowRecord storage r = _bRecord.borrows [loanID];
        uint256 remaining = principalAmount;
        for (uint256 i=0; i< r.lenders.length; i++) {
            address lAddress = r.lenders [i].lender;
            uint256 borrowedFromThisLender = 0;
            for (uint256 j=0; j<r.lenders [i].depositAccountIDs.length; j++){
                uint256 id = r.lenders [i].depositAccountIDs [j];
                borrowedFromThisLender += depositPool.receive_repayment_lentout_principal (_borrowersAddress, lAddress, id);
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
        return depositPool.receive_interest_for_lender_deposit_record(
            borrower, loanID, lender, depositID, interestAmount, principalAmount
        );
    }


    function pay_interest  (address _borrowersAddress, uint256 loanID, uint256 interestAmount, uint256 principalAmount) internal  { 
        BorrowerRecord storage _bRecord = borrowers [_borrowersAddress];
        BorrowRecord storage r = _bRecord.borrows [loanID];
        uint256 remaining = interestAmount;
        uint256 interestToThisLender = 0;
        for (uint256 i=0;i< r.lenders.length; i++){
            Lender memory _lender = r.lenders [i]; 
            address lAddress = _lender.lender; 
            for (uint256 j=0; j < _lender.depositAccountIDs.length; j++){
                uint256 depositID = _lender.depositAccountIDs [j];
                interestToThisLender += pay_interest_deposit (
                    _borrowersAddress, loanID, lAddress, depositID, interestAmount, principalAmount);
            }
            remaining -= interestToThisLender;
        }
        require (remaining == 0, "not all interest payment was successful");

    }

    function pay_protocol_reward (address _borrowersAddress, uint256 loanID, uint256 amount) 
    internal {
        treasury.reciveERC20Deposit (usdcContract, _borrowersAddress, amount);
        treasury.updateProtocolRewardRecord (amount, _borrowersAddress, loanID);
    }

    function pay_remaining_to_treasury (address _borrowersAddress, uint256 amount, string memory context) 
    internal {
        treasury.reciveERC20Deposit (usdcContract, _borrowersAddress, amount);
        treasury.updateMiscRecievedRecord (amount, context);
    }

    function repay_loan_principal_interest_protocol_reward (address _borrowersAddress, uint256 loanID, uint256 amount) 
    external 
    onlyExistingBorrower(_borrowersAddress){
        RepaymentComponent memory rep = calculate_repayment_components (_borrowersAddress, loanID);
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
        repay_loan_principal (_borrowersAddress, loanID, rep.pAmount);
        remaining -= rep.pAmount;

        if (remaining > 0) 
            pay_remaining_to_treasury (_borrowersAddress, amount, "");

    }


}