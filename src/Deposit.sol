//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Params} from "./Params.sol";
import {DepositPool} from "./DepositPool.sol";

contract Deposit is DepositPool {

    struct DepositRecord {
        uint256 amount;
        uint256 depositTime;
        uint256 lockupPeriod;
    }

    struct Depositor {
        uint256 totalAmount;
        DepositRecord[] deposits;
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

    modifier depositCheck (uint256 amount, uint256 lockupPeriod) {
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
            _;
    }

    function getDepositorInfo(address depositor) external view returns (Depositor memory) {
        return depositors[depositor];
    }

    function deposit_funds (address depositor_address, uint256 amount, uint256 lockupPeriod) 
                external depositCheck (amount,lockupPeriod) {
        bool success = deposit_usdc (depositor_address, amount); // Call to DepositPool to handle USDC transfe
        
        if (!success) 
            revert("Deposit failed: USDC transfer unsuccessful in deposit_funds ()");

        Depositor storage depositor = depositors[depositor_address];
        depositor.totalAmount += amount;
        depositor.deposits.push(DepositRecord({
            amount: amount,
            depositTime: block.timestamp,
            lockupPeriod: lockupPeriod
        }));
        depositor.isActive = true;

    }

}