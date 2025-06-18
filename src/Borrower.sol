//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Params} from "./Params.sol";
import {PriceConverter} from "../src/helper/PriceConverter.sol";
import {Deposit} from "./Deposit.sol";
import {Collateral} from "./Collateral.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

    struct BorrowRecord {
        uint256 amount;
        uint256 borrowTime;
        uint256 interestRate;
        uint256 l2b; 
    }



    struct BorrowerRecord {
        address borrowerAddress;
        uint256 totalBorrowed;
        mapping(uint256 => BorrowRecord) borrows; // Maps borrow index to BorrowRecord
        uint256 borrowCount; // To keep track of the number of borrows
    }

    mapping(address => BorrowerRecord) private borrowers;

    Params private params;
    AggregatorV3Interface private priceFeed;
    Deposit private depositPool;
    Collateral private collateralPool;
    
    IERC20 private usdcContract;

    modifier onlyExistingBorrower(address _borrowerAddress) {
        require(borrowerExists(_borrowerAddress), "Borrower does not exist");
        _;
    }
    constructor (Params _params, address _priceFeedAddress, address _depositContractAddress, address _collateralContractAddress) {
        // Initialize any necessary parameters or state variables
        params = _params;
        depositPool = Deposit (_depositContractAddress);
        collateralPool = Collateral (_collateralContractAddress);
        priceFeed = AggregatorV3Interface (_priceFeedAddress);
        usdcContract = depositPool.getUSDCContract();
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
        require (depositPool.withdraw_usdc_to_borrower(_borrowerAddress, _liquidityToBorrow), "USDC withdrawal to borrower failed");
        require (collateralPool.isCollateralAvailableForBorrow (_borrowerAddress, _correspondingColletaralID), "Collateral already borrowed against");
        
        BorrowerRecord storage borrower = borrowers[_borrowerAddress];
        borrower.totalBorrowed += _liquidityToBorrow;
        borrower.borrows [_correspondingColletaralID] = BorrowRecord({
            amount: _liquidityToBorrow,
            borrowTime: block.timestamp,
            interestRate: params.getBaseInterestRate(),
            l2b: collateralPool.getCollateralL2BByRecord(_borrowerAddress, _correspondingColletaralID)
        }); 
        emit LendingDone(
            _borrowerAddress,
            _correspondingColletaralID,
            _liquidityToBorrow,
            borrower.totalBorrowed,
            block.timestamp
        );
    }
}