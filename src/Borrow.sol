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

contract Borrow {
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

    modifier only_existing_borrower(address _borrowerAddress) {
        require(borrower_exists(_borrowerAddress), "Borrower does not exist");
        _;
    }

    modifier only_active_loan(address _borrowerAddress, uint256 _correspondingColletaralID) {
        require(borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount > 0, "No active loan for this collateral");
        _;
    }

    modifier enough_for_repayment (address _borrowerAddress, uint256 _correspondingColletaralID, uint256 _repaymentAmount) {
        require(_repaymentAmount > 0, "Repayment amount must be greater than zero");
        uint256 borrowedAmount = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;
        require(_repaymentAmount <= borrowedAmount, "Repayment amount exceeds borrowed amount");
        uint256 interestRate = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;
        uint256 interestPayable = (borrowedAmount * interestRate * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)) / (365 days * 100);
        require(_repaymentAmount >= interestPayable, "Repayment amount must cover interest payable");
        uint256 protocolReward = (borrowedAmount * params.get_reserve_factor() * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)) / (365 days * 100);
        require(_repaymentAmount >= interestPayable + protocolReward, "Repayment amount must cover interest and protocol reward");
        _;
    }

    constructor (Params _params, 
            address _priceFeedAddress, 
            address _depositContractAddress, 
            address _collateralContractAddress,
            IERC20 _usdcContract) {
        // Initialize any necessary parameters or state variables
        params = _params;
        depositPool = Deposit (_depositContractAddress);
        collateralPool = Collateral (_collateralContractAddress);
        priceFeed = AggregatorV3Interface (_priceFeedAddress);
        usdcContract = _usdcContract;
        //payable, because Treasury implements fallback
    }

    function get_borrowed_amount (address _borrowerAddress, uint256 _correspondingColletaralID) 
        external 
        view 
        only_existing_borrower(_borrowerAddress)         
        returns (uint256) 
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;    
    }

    function get_borrowed_interest_rate (address _borrowerAddress, uint256 _correspondingColletaralID) 
        external 
        view 
        only_existing_borrower(_borrowerAddress)         
        returns (uint256) 
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;    
    }

    function get_borrow_record (address _borrowersAddress, uint256 _loanID) public view returns (BorrowRecord memory) {
        BorrowRecord memory record = borrowers [_borrowersAddress].borrows [_loanID];
        return record;
    }

    function get_interest_payable (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) 
        external 
        view 
        only_existing_borrower(_borrowerAddress)         
        returns (uint256) 
    {
        BorrowRecord storage borrowRecord = borrowers[_borrowerAddress].borrows[_correspondingColletaralID];
        uint256 timeElapsed = block.timestamp - borrowRecord.borrowTime;
        uint256 interestPayable = (borrowRecord.amount * borrowRecord.interestRate * timeElapsed) / (365 days * 100);
        return interestPayable;
    }

    function get_protocol_reward (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) 
        external 
        view 
        only_existing_borrower(_borrowerAddress)         
        returns (uint256) 
    {
        BorrowRecord storage borrowRecord = borrowers[_borrowerAddress].borrows[_correspondingColletaralID];
        uint256 timeElapsed = block.timestamp - borrowRecord.borrowTime;
        uint256 protocolReward = (borrowRecord.amount * params.get_reserve_factor() * timeElapsed) / (365 days * 100);
        return protocolReward;
    }

    function calculate_interest_amount (BorrowerRecord storage _bRecord, BorrowRecord storage r) internal view returns (uint256){
        return (r.interestRate * (_bRecord.totalBorrowed * (block.timestamp -  r.borrowTime))  / (365 days * 100));

    }

    function calculate_protocol_reward  (BorrowerRecord storage _bRecord, BorrowRecord storage r) internal view returns (uint256) {
        return (params.get_reserve_factor() *  (_bRecord.totalBorrowed * (block.timestamp -  r.borrowTime))  / (365 days * 100));
    }

    function calculate_repayment_components (address _borrowersAddress, uint256 loanID) 
    public view returns (RepaymentComponent memory){
        RepaymentComponent memory rep;
        BorrowerRecord storage _bRecord = borrowers [_borrowersAddress];
        BorrowRecord storage r = _bRecord.borrows [loanID];
        rep.pAmount = r.amount;
        rep.iAmount = calculate_interest_amount( _bRecord, r);
        rep.rAmount = calculate_protocol_reward (_bRecord, r);
        return rep;
    }

    function calculate_liquidity_to_borrow (address _borrowerAddress) public view only_existing_borrower (_borrowerAddress) returns (uint256)  {
        uint256 usdcValue = 0;
        BorrowerRecord storage borrowerRecord = borrowers[_borrowerAddress];
        
        for (uint256 i = 0; i < borrowerRecord.borrowCount; i++) {
            if (!collateralPool.is_collateral_available(_borrowerAddress, i)){ 
                uint256 collateralL2B = collateralPool.get_collateralL2B_by_record(_borrowerAddress, i);
                uint256 collateralETH = collateralPool.get_collateral_ETH_by_record (_borrowerAddress, i);
                uint256 collateralETHToUSDC = collateralETH.ethToUSD(priceFeed);
                uint256 adjustedUsdcValue = (collateralETHToUSDC * collateralL2B) / 100;
                usdcValue += adjustedUsdcValue;
            }
        }
        return  usdcValue; // Adjust based on your L2B logic
    }

    function calculate_liquidity_to_borrow_for_collateral (address _borrowerAddress, uint256 _correspondingColletaralID) public view only_existing_borrower (_borrowerAddress) returns (uint256) {
        uint256 collateralL2B = collateralPool.get_collateralL2B_by_record(_borrowerAddress, _correspondingColletaralID);
        uint256 collateralETH = collateralPool.get_collateral_ETH_by_record (_borrowerAddress, _correspondingColletaralID);
        uint256 collateralETHToUSDC = collateralETH.ethToUSD(priceFeed);
        return (collateralETHToUSDC * collateralL2B) / 100; // Adjust based on your L2B logic
    }

    function borrower_exists(address _borrowerAddress) public view returns (bool) {
        return borrowers[_borrowerAddress].borrowerAddress != address(0);
    }


    function add_new_borrower (
        address _borrowerAddress,
        uint256 _totalCollateral,
        uint256 _totalBorrowed,
        uint256 _interestRate,
        uint256 _l2b
    ) external {
        require (borrower_exists(_borrowerAddress) == false, "Borrower already exists");
        
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

    function lend_for_collateral (
        address _borrowerAddress,
        uint256 _correspondingColletaralID
    ) external only_existing_borrower (_borrowerAddress){
        // the deposit pull must have enough usdc to lend
        uint256 _liquidityToBorrow = calculate_liquidity_to_borrow_for_collateral (_borrowerAddress, _correspondingColletaralID); 
        
        require (_liquidityToBorrow <= depositPool.get_pool_balance(), "Not enough liquidity in the pool");
        require (collateralPool.is_collateral_available (_borrowerAddress, _correspondingColletaralID), "Collateral already borrowed against");
        
        Lender [] memory _lenders =  depositPool.lend_to_borrower (_borrowerAddress, _liquidityToBorrow);
        BorrowerRecord storage borrower = borrowers[_borrowerAddress];
        borrower.totalBorrowed += _liquidityToBorrow;
        // Create the borrow record without assigning `lenders` yet
        BorrowRecord storage record = borrower.borrows[_correspondingColletaralID];
        record.loanID = _correspondingColletaralID;
        record.amount = _liquidityToBorrow;
        record.borrowTime = block.timestamp;
        record.interestRate = params.get_base_interest_rate();
        record.l2b = collateralPool.get_collateralL2B_by_record(_borrowerAddress, _correspondingColletaralID);
        
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
}