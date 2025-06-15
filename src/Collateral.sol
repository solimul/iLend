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

  
    mapping (address => CollateralDepositor) private CollateralDepositors;

    constructor(Params _params) CollateralPool () {
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
}