//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Params} from "./Params.sol";
import {PriceConverter} from "../src/helper/PriceConverter.sol";
import {Deposit} from "./Deposit.sol";
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



    struct BorrowerRecord {
        address borrowerAddress;
        uint256 totalCollateral;
        uint256 totalBorrowed;
        uint256 [] borrows;
        uint256 [] borrowsTime;
        uint256 interestRate;
        uint256 l2b; // Loan to Borrower ratio
    }

    mapping(address => BorrowerRecord) private borrowers;
    Params private params;
    AggregatorV3Interface private priceFeed;
    Deposit private depositPool;
    IERC20 private usdcContract;

    modifier onlyExistingBorrower(address _borrowerAddress) {
        require(borrowerExists(_borrowerAddress), "Borrower does not exist");
        _;
    }
    constructor (Params _params, AggregatorV3Interface _priceFeed, address _depositContractAddress) {
        // Initialize any necessary parameters or state variables
        params = _params;
        depositPool = Deposit (_depositContractAddress);
        priceFeed = _priceFeed;
        usdcContract = depositPool.getUSDCContract();
    }

    function calculateLiquidityToBorrow(
        address _borrowerAddress,
        uint256 _collateralAmount
    ) public view onlyExistingBorrower (_borrowerAddress) returns (uint256)  {
        uint256 usdcValue = _collateralAmount.ethToUSD (priceFeed);
        uint256 l2b =  borrowers[_borrowerAddress].l2b;
        return (usdcValue * l2b) / 100; // Adjust based on your L2B logic
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
        borrowers[_borrowerAddress] = BorrowerRecord({
                borrowerAddress: _borrowerAddress,
                totalCollateral: _totalCollateral,
                totalBorrowed: _totalBorrowed,
                interestRate: _interestRate,
                borrows: new uint256[](0),
                borrowsTime: new uint256[](0),
                l2b: params.getL2B()
        });

        emit NewBorrowerAdded(
                _borrowerAddress,
                _totalCollateral,
                _totalBorrowed,
                _interestRate,
                _l2b
        );   
    }

    function lend (
        address _borrowerAddress,
        uint256 _colleteralAmount
    ) external onlyExistingBorrower(_borrowerAddress){
        // the deposit pull must have enough usdc to lend
        uint256 _liquidityToBorrow = calculateLiquidityToBorrow (_borrowerAddress, _colleteralAmount); 
        require (_liquidityToBorrow <= depositPool.getPoolBalance(), "Not enough liquidity in the pool");
        require (depositPool.withdraw_usdc_to_borrower(_borrowerAddress, _liquidityToBorrow), "USDC withdrawal to borrower failed");
        BorrowerRecord storage borrower = borrowers[_borrowerAddress];
        borrower.totalBorrowed += _liquidityToBorrow;
        borrower.borrows.push(_liquidityToBorrow);
        borrower.borrowsTime.push(block.timestamp);
        
    }
}