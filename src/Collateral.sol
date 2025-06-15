//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CollateralPool} from "./CollateralPool.sol";
import {Params} from "./Params.sol";

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
        uint256 lastInterestWithdrawTimeForRecord; // Time of the last interest withdrawal
    }

    struct CollateralDepositor {
        uint256 totalAmount;
        CollateralDepositRecord[] deposits;
        CollateralWithdrawalRecord [] collateralWithdrawalRecord;
        bool isActive;
    }

  
    mapping (address => CollateralDepositor) private CollateralDepositors;

    constructor(address priceFeedManagerAddress, Params _params) CollateralPool (priceFeedManagerAddress)  {
        params = _params;
    }

    function depositCollateral(uint256 amount, address depositor) external returns (bool) {
        require(amount <= params.getMaxCollateralAmount (), "Amount must be less than or equal to the maximum collateral amount");
        require(amount >= params.getMinCollateralAmount (), "Amount must be greater than or equal to the minimum collateral amount");
        bool success = eth_contract.transferFrom(depositor, address(this), amount);
        require(success, "Transfer failed");
        CollateralDepositor storage collateralDepositor = CollateralDepositors[depositor];
        if (!collateralDepositor.isActive) {
            collateralDepositor.isActive = true;
        }
        collateralDepositor.totalAmount += amount;
        CollateralDepositRecord memory newDeposit = CollateralDepositRecord({
            amount: amount,
            depositTime: block.timestamp,
            lastInterestWithdrawTimeForRecord: block.timestamp
        });
        collateralDepositor.deposits.push(newDeposit);
        emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount);

        return true;
    }
}