//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CollateralPool} from "./CollateralPool.sol";
import {Params} from "./Params.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract Collateral is CollateralPool {

    event CollateralDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 depositTime,
        uint256 totalCollateral,
        uint256 depositCounts
    );

    Params private params;


    struct CollateralWithdrawalRecord {
        uint256 amountWithdrawn;
        uint256 withdrawTime;
    }

    struct CollateralDepositRecord {
        uint256 amount;
        uint256 depositTime;
        uint256 l2b; // Assuming l2b is a value associated with the deposit
        bool hasBorrowedAgainst;
    }

    

    struct CollateralDepositor {
        uint256 totalAmount;
        mapping (uint256 => CollateralDepositRecord) collateralDepositRecords;
        CollateralWithdrawalRecord [] collateralWithdrawalRecord;
        bool isActive;
        uint256 depositCounts; // To keep track of the number of deposits
    }
    // Mapping to store collateral depositors

  
    mapping (address => CollateralDepositor) private collateralDepositors;

    constructor(Params _params, address _priceFeedAddress) CollateralPool (_priceFeedAddress) {
        params = _params;
    } 

    modifier depositCheck (uint256 amount) {
        require(amount >= params.getMinCollateralAmount (),string(
            abi.encodePacked(
            "Collateral deposit must be >= ",
            Strings.toString(params.getMinCollateralAmount())
            )));
        require(amount <= params.getMaxCollateralAmount (),string(
            abi.encodePacked(
            "Collateral deposit must be <= ",
            Strings.toString(params.getMaxCollateralAmount())
            )));
            _;
    }

    modifier onlyActiveDepositor(address depositor) {
        require(collateralDepositors[depositor].isActive, "Not an active depositor");
        _;
    }
    modifier onlyValidDepositIndex(address depositor, uint256 depositIndex) {
        require(depositIndex < collateralDepositors[depositor].depositCounts, "Invalid deposit index");
        _;
    }

    function deposit_collateral (address depositor, uint256 amount) external depositCheck (amount) returns (bool)  {
        require(deposit_eth(depositor, amount), "Transfer failed");

        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        if (!collateralDepositor.isActive) {
            collateralDepositor.isActive = true;
        }
        collateralDepositor.totalAmount += amount;
        CollateralDepositRecord memory newDeposit = CollateralDepositRecord({
            amount: amount,
            hasBorrowedAgainst: false, // Initially, the deposit has not been borrowed against
            l2b: params.getL2B(), // Assuming L2B is a parameter set in Params
            depositTime: block.timestamp
        });
        collateralDepositor.collateralDepositRecords [collateralDepositor.depositCounts] = newDeposit;
        collateralDepositor.depositCounts += 1;
        emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount, collateralDepositor.depositCounts);

        return true;
    }

    function withdraw_collateral(address depositor, uint256 amount) external {
        CollateralDepositor storage collateralDepositor = collateralDepositors [depositor];
        require(collateralDepositor.isActive, "Not an active depositor");
        require(collateralDepositor.totalAmount >= amount, "Insufficient collateral");

        collateralDepositor.totalAmount -= amount;
        CollateralWithdrawalRecord memory withdrawalRecord = CollateralWithdrawalRecord({
            amountWithdrawn: amount,
            withdrawTime: block.timestamp
        });
        collateralDepositor.collateralWithdrawalRecord.push(withdrawalRecord);

        // Transfer the collateral back to the depositor
        require(eth_contract.transfer(depositor, amount), "Transfer failed");

        //emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount);
    }

    function updateCollateralDepositor(
        address depositor,
        uint256 depositIndex,
        bool hasBorrowedAgainst
    ) external 
            onlyActiveDepositor(depositor) 
            onlyValidDepositIndex(depositor, depositIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        collateralDepositor.collateralDepositRecords[depositIndex].hasBorrowedAgainst = hasBorrowedAgainst;
    }

    function getCollateralDepositorsDepositCount(address depositor) external view 
        onlyActiveDepositor(depositor) 
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.depositCounts;
    }

    function getCollateralETHByRecord (
        address depositor,
        uint256 recordIndex
    ) external view 
        onlyActiveDepositor(depositor) 
        onlyValidDepositIndex(depositor, recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.collateralDepositRecords[recordIndex].amount;
    }

    function getCollateralL2BByRecord (
        address depositor,
        uint256 recordIndex
    ) external view 
        onlyActiveDepositor(depositor) 
        onlyValidDepositIndex(depositor, recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.collateralDepositRecords[recordIndex].l2b;
    }

    function updateBorrowedAgainstCollateral (
        address depositor,
        uint256 recordIndex,
        bool hasBorrowedAgainst
    ) external 
        onlyActiveDepositor(depositor) 
        onlyValidDepositIndex(depositor, recordIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        collateralDepositor.collateralDepositRecords[recordIndex].hasBorrowedAgainst = hasBorrowedAgainst;
    }

    function isCollateralAvailableForBorrow(
        address depositor,
        uint256 recordIndex
    ) external view 
            onlyActiveDepositor(depositor) 
            onlyValidDepositIndex(depositor, recordIndex)  
            returns (bool)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return !collateralDepositor.collateralDepositRecords[recordIndex].hasBorrowedAgainst;
    }    
}