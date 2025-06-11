//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Params} from "./Params.sol";
import {DepositPool} from "./DepositPool.sol";

contract Deposit is DepositPool {

    event DepositDone(address indexed depositor, uint256 amount, uint256 timestamp);
    struct Depositor {
        uint256 amount;
        uint256 [] indexedAmount; // Assuming indexed_amount is an array to track deposits
        uint256 [] indexedDepositTime; // Assuming indexed_deposit_time is an array to track deposit times
        uint256 [] indexedLockupPeriod; // Assuming indexed_lockup_period is an array to track lockup periods
        bool isActive;
    }

    Params public params;
    
    mapping (address => Depositor) private depositors;

    constructor(Params _params) DepositPool(msg.sender) {
        params = _params;
        // Initialize the contract if needed
    }
    
    modifier onlyDepositor() {
        require (depositors[msg.sender].isActive, "Not a depositor");
        _;
    }

    function getDepositorInfo(address depositor) external view returns (Depositor memory) {
        return depositors[depositor];
    }

    function deposit_funds (address depositor_address, uint256 amount, uint256 lockupPeriod) external {
        require(amount >= params.getMinDeposit (),string(
            abi.encodePacked(
            "Deposit must be >= ",
            Strings.toString(params.getMinDeposit())
            )));
        require(amount <= params.getMaxDeposit (),string(
            abi.encodePacked(
            "Deposit must be <= ",
            Strings.toString(params.getMaxDeposit())
            )));

        require(lockupPeriod >= params.getMinLockupPeriod (),string(
            abi.encodePacked(
            "Lockup period must be >= ",
            Strings.toString(params.getMinLockupPeriod())
            )));

        require(lockupPeriod <= params.getMaxLockupPeriod (),string(
            abi.encodePacked(
            "Lockup period must be <= ",
            Strings.toString(params.getMaxLockupPeriod())
            )));
        
        Depositor storage depositor = depositors[depositor_address];


        deposit_usdc (depositor_address, amount); // Call to DepositPool to handle USDC transfe


        depositor.amount += amount;
        uint256 len = depositor.indexedAmount.length;
        depositor.indexedAmount [len-1] = amount; // Assuming indexed_amount is an array to track deposits
        depositor.indexedDepositTime [len-1] = block.timestamp;
        depositor.indexedLockupPeriod [len - 1] = lockupPeriod;
        depositor.isActive = true;

        emit DepositDone(depositor_address, amount, block.timestamp);
    }

}