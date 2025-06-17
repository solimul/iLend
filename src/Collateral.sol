//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CollateralPool} from "./CollateralPool.sol";
import {Params} from "./Params.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";

contract Collateral is CollateralPool {

    event CollateralDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 depositTime,
        uint256 totalCollateral
    );

    Params private params;


    struct CollateralWithdrawalRecord {
        uint256 amountWithdrawn;
        uint256 withdrawTime;
    }

    struct CollateralDepositRecord {
        uint256 amount;
        uint256 depositTime;
    }

    struct CollateralDepositor {
        uint256 totalAmount;
        CollateralDepositRecord[] deposits;
        CollateralWithdrawalRecord [] collateralWithdrawalRecord;
        bool isActive;
    }
    // Mapping to store collateral depositors

  
    mapping (address => CollateralDepositor) private CollateralDepositors;

    constructor(Params _params, AggregatorV3Interface _priceFeed) CollateralPool (_priceFeed) {
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

    function deposit_collateral (address depositor, uint256 amount) external depositCheck (amount) returns (bool)  {
        require(deposit_eth(depositor, amount), "Transfer failed");

        CollateralDepositor storage collateralDepositor = CollateralDepositors[depositor];
        if (!collateralDepositor.isActive) {
            collateralDepositor.isActive = true;
        }
        collateralDepositor.totalAmount += amount;
        CollateralDepositRecord memory newDeposit = CollateralDepositRecord({
            amount: amount,
            depositTime: block.timestamp
        });
        collateralDepositor.deposits.push(newDeposit);
        emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount);

        return true;
    }

    function withdraw_collateral(address depositor, uint256 amount) external {
        CollateralDepositor storage collateralDepositor = CollateralDepositors [depositor];
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

        emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount);
    }
}