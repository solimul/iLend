//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Params} from "../misc/Params.sol";
import {PriceConverterLib} from "../lib/PriceConverterLib.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lender, InterestEarned} from "../shared/SharedStructures.sol";
import {Treasury} from "../treasury/Treasury.sol";
import {RepaymentComponent, BorrowRecord, BorrowerRecord} from "../shared/SharedStructures.sol";
import {iLend} from "../ILend.sol";
import {console} from "../../lib/forge-std/src/Script.sol";

contract Borrow {
    using PriceConverterLib for uint256;

    error InvalidBorrowerContractAddress();

    error BorrowerDoesNotExist(address borrower);
    error NoActiveLoanForCollateral(address borrower, uint256 collateralID);

    error RepaymentAmountZero();
    error RepaymentAmountExceedsBorrowed(uint256 repayment, uint256 borrowed);
    error RepaymentLessThanInterest(uint256 repayment, uint256 interestDue);
    error RepaymentLessThanInterestAndReward(uint256 repayment, uint256 totalDue);

    error BorrowerAlreadyExists(address borrower);

    error InsufficientPoolLiquidity(uint256 requested, uint256 available);
    error CollateralAlreadyUsed(address borrower, uint256 collateralID);
    error OnlyILendContractCanAccessThisFunction(address sender, address ilend);
    error OnlyOwnerCanAccessThisFunction(address sender, address owner);

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

    event WithdrawnToBorrower(address indexed borrower, uint256 amount, uint256 poolBalance, uint256 timestamp);

    mapping(address => BorrowerRecord) private borrowers;
    address[] sBorrowersList;

    uint256 private sTotalBorrowedOutUSDC; 

    Params private params;
    AggregatorV3Interface private priceFeed;
    Deposit private depositPool;
    Collateral private collateralPool;
    Treasury private treasury;

    IERC20 private usdcContract;
    address private facadeContractAddress;
    address private immutable iOwnerAddress;

    modifier only_existing_borrower(address _borrowerAddress) {
        if (!borrower_exists(_borrowerAddress)) {
            revert BorrowerDoesNotExist(_borrowerAddress);
        }
        _;
    }

    modifier only_active_loan(address _borrowerAddress, uint256 _correspondingColletaralID) {
        if (borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount == 0) {
            revert NoActiveLoanForCollateral(_borrowerAddress, _correspondingColletaralID);
        }
        _;
    }

    modifier only_facade_contract(address _sender) {
        if (_sender != facadeContractAddress) {
            revert OnlyILendContractCanAccessThisFunction(_sender, facadeContractAddress);
        }
        _;
    }

    modifier only_owner_contract(address _sender) {
        if (_sender != iOwnerAddress) {
            revert OnlyOwnerCanAccessThisFunction(_sender, iOwnerAddress);
        }
        _;
    }

    modifier enough_for_repayment(
        address _borrowerAddress,
        uint256 _correspondingColletaralID,
        uint256 _repaymentAmount
    ) {
        if (_repaymentAmount == 0) {
            revert RepaymentAmountZero();
        }

        uint256 borrowedAmount = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;
        if (_repaymentAmount > borrowedAmount) {
            revert RepaymentAmountExceedsBorrowed(_repaymentAmount, borrowedAmount);
        }

        uint256 interestRate = borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;
        uint256 interestPayable = (
            borrowedAmount * interestRate
                * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)
        ) / (365 days * 100);

        if (_repaymentAmount < interestPayable) {
            revert RepaymentLessThanInterest(_repaymentAmount, interestPayable);
        }

        uint256 protocolReward = (
            borrowedAmount * params.get_reserve_factor()
                * (block.timestamp - borrowers[_borrowerAddress].borrows[_correspondingColletaralID].borrowTime)
        ) / (365 days * 100);

        uint256 totalDue = interestPayable + protocolReward;
        if (_repaymentAmount < totalDue) {
            revert RepaymentLessThanInterestAndReward(_repaymentAmount, totalDue);
        }

        _;
    }

    constructor(
        address _paramsAddress,
        address _priceFeedAddress,
        address _depositContractAddress,
        address _collateralContractAddress,
        address _usdcContractAddress
    ) {
        // Initialize any necessary parameters or state variables
        params = Params(_paramsAddress);
        depositPool = Deposit(_depositContractAddress);
        collateralPool = Collateral(_collateralContractAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        usdcContract = IERC20(_usdcContractAddress);
        iOwnerAddress = msg.sender;
        sTotalBorrowedOutUSDC = 0;
        //payable, because Treasury implements fallback
    }

    function get_borrowed_amount(address _borrowerAddress, uint256 _correspondingColletaralID)
        external
        view
        only_existing_borrower(_borrowerAddress)
        returns (uint256)
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].amount;
    }

    function get_borrowed_interest_rate(address _borrowerAddress, uint256 _correspondingColletaralID)
        external
        view
        only_existing_borrower(_borrowerAddress)
        returns (uint256)
    {
        return borrowers[_borrowerAddress].borrows[_correspondingColletaralID].interestRate;
    }

    function get_borrow_record(address _borrowersAddress, uint256 _loanID) public view returns (BorrowRecord memory) {
        BorrowRecord memory record = borrowers[_borrowersAddress].borrows[_loanID];
        return record;
    }

    function get_interest_payable(address _borrowerAddress, uint256 _correspondingColletaralID)
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

    function get_protocol_reward(address _borrowerAddress, uint256 _correspondingColletaralID)
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

    function get_current_borrowed_out_usdc () external view returns (uint256) {
        return sTotalBorrowedOutUSDC;
    }

    function calculate_interest_amount(BorrowerRecord storage _bRecord, BorrowRecord storage r)
        internal
        view
        returns (uint256)
    {
        return (r.interestRate * (_bRecord.totalBorrowed * (block.timestamp - r.borrowTime)) / (365 days * 100));
    }

    function calculate_protocol_reward(BorrowerRecord storage _bRecord, BorrowRecord storage r)
        internal
        view
        returns (uint256)
    {
        return (
            params.get_reserve_factor() * (_bRecord.totalBorrowed * (block.timestamp - r.borrowTime)) / (365 days * 100)
        );
    }

    function calculate_repayment_components(address _borrowersAddress, uint256 _loanID)
        public
        view
        returns (RepaymentComponent memory)
    {
        RepaymentComponent memory rep;
        BorrowerRecord storage _bRecord = borrowers[_borrowersAddress];
        BorrowRecord storage r = _bRecord.borrows[_loanID];
        rep.pAmount = r.amount;
        rep.iAmount = calculate_interest_amount(_bRecord, r);
        rep.rAmount = calculate_protocol_reward(_bRecord, r);
        return rep;
    }

    function calculate_liquidity_to_borrow(address _borrowerAddress)
        public
        view
        only_existing_borrower(_borrowerAddress)
        returns (uint256)
    {
        uint256 usdcValue = 0;
        BorrowerRecord storage borrowerRecord = borrowers[_borrowerAddress];

        for (uint256 i = 0; i < borrowerRecord.borrowCount; i++) {
            if (!collateralPool.is_collateral_available(_borrowerAddress, i)) {
                uint256 collateralL2B = collateralPool.get_collateralL2B_by_record(_borrowerAddress, i);
                uint256 collateralETH = collateralPool.get_collateral_ETH_by_record(_borrowerAddress, i);
                uint256 collateralETHToUSDC = collateralETH.eth_to_USDC(priceFeed);
                uint256 adjustedUsdcValue = (collateralETHToUSDC * collateralL2B) / 100;
                usdcValue += adjustedUsdcValue;
            }
        }
        return usdcValue; // Adjust based on your L2B logic
    }

    function calculate_liquidity_to_borrow_for_collateral(address _borrowerAddress, uint256 _correspondingColletaralID)
        public
        view
        only_existing_borrower(_borrowerAddress)
        returns (uint256)
    {
        uint256 collateralL2B = collateralPool.get_collateralL2B_by_record(_borrowerAddress, _correspondingColletaralID);
        uint256 collateralETH =
            collateralPool.get_collateral_ETH_by_record(_borrowerAddress, _correspondingColletaralID);
        collateralETH = collateralETH.convert_WEI_to_ETH(); // WEI to Ether
        uint256 collateralETHToUSDC = collateralETH.eth_to_USD_WEI(priceFeed);
        return (collateralETHToUSDC * collateralL2B) / 100; // Adjust based on your L2B logic
    }

    function borrower_exists(address _borrowerAddress) public view returns (bool) {
        return borrowers[_borrowerAddress].borrowerAddress != address(0);
    }

    function add_new_borrower(
        address _borrowerAddress,
        uint256 _totalCollateral,
        uint256 _totalBorrowed,
        uint256 _interestRate,
        uint256 _l2b
    ) external only_facade_contract(msg.sender) {
        if (borrower_exists(_borrowerAddress)) {
            revert BorrowerAlreadyExists(_borrowerAddress);
        }

        BorrowerRecord storage b = borrowers[_borrowerAddress];
        b.borrowerAddress = _borrowerAddress;
        b.totalBorrowed = _totalBorrowed;
        b.borrowCount = 0;

        sBorrowersList.push(_borrowerAddress);
        emit NewBorrowerAdded(_borrowerAddress, _totalCollateral, _totalBorrowed, _interestRate, _l2b);
    }

    function update_borrow_records(address _borrowerAddress, uint256 _correspondingColletaralID)
        external
        only_facade_contract(msg.sender)
        only_existing_borrower(_borrowerAddress)
        returns (uint256)
    {
        // the deposit pull must have enough usdc to lend
        uint256 _liquidityToBorrow =
            calculate_liquidity_to_borrow_for_collateral(_borrowerAddress, _correspondingColletaralID);

        uint256 poolBalance = depositPool.get_deposit_balance();
        if (_liquidityToBorrow > poolBalance) {
            revert InsufficientPoolLiquidity(_liquidityToBorrow, poolBalance);
        }

        if (!collateralPool.is_collateral_available(_borrowerAddress, _correspondingColletaralID)) {
            revert CollateralAlreadyUsed(_borrowerAddress, _correspondingColletaralID);
        }

        Lender[] memory _lenders = depositPool.match_update_lenders(_liquidityToBorrow);
        depositPool.update_lentout_amount(_liquidityToBorrow);

        BorrowerRecord storage borrower = borrowers[_borrowerAddress];
        borrower.totalBorrowed += _liquidityToBorrow;
        borrower.borrowCount += 1;
        // Create the borrow record without assigning `lenders` yet
        BorrowRecord storage record = borrower.borrows[_correspondingColletaralID];
        record.loanID = _correspondingColletaralID;
        record.amount = _liquidityToBorrow;
        record.borrowTime = block.timestamp;
        record.interestRate = params.get_base_interest_rate();
        record.l2b = collateralPool.get_collateralL2B_by_record(_borrowerAddress, _correspondingColletaralID);

        // Manually copy each Lender from _lenders (memory) to record.lenders (storage)
        for (uint256 i = 0; i < _lenders.length; i++) {
            record.lenders.push(_lenders[i]);
        }

        sTotalBorrowedOutUSDC += _liquidityToBorrow;

        emit LendingDone(
            _borrowerAddress, _correspondingColletaralID, _liquidityToBorrow, borrower.totalBorrowed, block.timestamp
        );
        return _liquidityToBorrow;
    }

    function update_loan_closing (uint256 _usdcAmount) 
    public
    only_facade_contract (msg.sender)   {
        sTotalBorrowedOutUSDC -= _usdcAmount;
    }

    function yet_to_be_borrowed(address _borrowerAddress, uint256 _correspondingColletaralID)
        public
        view
        only_existing_borrower(_borrowerAddress)
        returns (bool)
    {
        BorrowRecord storage record = borrowers[_borrowerAddress].borrows[_correspondingColletaralID];
        return record.amount == 0;
    }

    function register_caller_contracts(address _iLendAddress) external only_owner_contract(msg.sender) {
        facadeContractAddress = _iLendAddress;
    }



    function test_get_borrower_record_attributes(address _borrower)
        public
        returns (uint256 borrowerCount, uint256 totalBorrowed, uint256 borrowCount, address borrowerAddress)
    {
        borrowerCount = sBorrowersList.length;
        borrowCount = 0;
        totalBorrowed = 0;
        borrowerAddress = address(0);
        if (borrowerCount > 0) {
            BorrowerRecord storage borrower = borrowers[_borrower];
            totalBorrowed = borrower.totalBorrowed;
            borrowCount = borrower.borrowCount;
            borrowerAddress = borrower.borrowerAddress;
        }
    }
}
