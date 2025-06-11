//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./Params.sol";

contract iLend {
    // Events
    event Deposit(address indexed user, uint256 amount, uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount, uint256 timestamp);
    event Borrow(address indexed user, uint256 amount, uint256 interestRate, uint256 timestamp);
    event Repay(address indexed user, uint256 amount, uint256 timestamp);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 amount, uint256 timestamp);


    
    Params public params;
    address public owner;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor () {
        owner = msg.sender;
        params = new Params(owner);
        params.initialize (false, false, false);
        setParams();
    }

    function setParams() internal {
        // Set initial parameters
        params.setDepositParams(1000, 1000000, 50, 1 days, 365 days);
        params.setBorrowParams(1000, 1000000, 50, 1 days, 365 days, 5, 20, 200, 50);
        params.setLiquidationParams(150, 10, 1000, 50000, 1000, 50000, 5, "percentage");
        params.setOracleParams(address(this), 60 seconds, 18);
        params.setCollateralParams(address(this), 1000, 1000000, 75, true);
    }
}