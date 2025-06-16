//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Params} from "./Params.sol";
import {DepositPool} from "./DepositPool.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Deposit is DepositPool {

    event DepositorPrincipalWithDrawalDone(
        address indexed depositPool,
        address indexed depositor,
        uint256 totalWithdrawable,
        uint256 amountWithdrawn,
        uint256 remainingBalanceForDepositor,
        uint256 poolBalance,
        uint256 timestamp
    );

    event DepositorInterestWithDrawalDone(
        address indexed depositPool,
        address indexed depositor,
        uint256 totalInterestIncome,
        uint256 amountWithdrawn,
        uint256 remainingBalanceForDepositor,
        uint256 poolBalance,
        uint256 timestamp
    );


    struct PrincipalWithdrawalRecord {
        uint256 amountWithdrawn;
        uint256 withdrawTime;
    }

    struct InterestWithdrawalRecord {
        uint256 amountWithdrawn;
        uint256 withdrawTime;
    }

    struct DepositRecord {
        uint256 amount;
        uint256 depositTime;
        uint256 lockupPeriod;
        uint256 lastInterestWithdrawTimeForRecord; // Time of the last interest withdrawal
    }

    struct Depositor {
        uint256 totalAmount;
        DepositRecord[] deposits;
        InterestWithdrawalRecord [] interestWithdrawalRecords;
        PrincipalWithdrawalRecord [] principalWithdrawalRecords;
        bool isActive;
    }

    Params public params;
    
    mapping (address => Depositor) private depositors;

    constructor(Params _params) DepositPool(msg.sender) {
        params = _params;
        // Initialize the contract if needed
    }
    
    modifier onlyDepositor(address depositor_address) {
        require (depositors[depositor_address].isActive, "Not a depositor");
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


    function deposit_liquidity (address depositor_address, uint256 amount, uint256 lockupPeriod) 
                external depositCheck (amount,lockupPeriod) {
        bool success = deposit_usdc (depositor_address, amount); // Call to DepositPool to handle USDC transfe
        
        if (!success) 
            revert("Deposit failed: USDC transfer unsuccessful in deposit_funds ()");

        Depositor storage depositor = depositors[depositor_address];
        depositor.totalAmount += amount;
        uint256 currentTime = block.timestamp;
        depositor.deposits.push(DepositRecord({
            amount: amount,
            depositTime: currentTime,
            lockupPeriod: lockupPeriod,
            lastInterestWithdrawTimeForRecord: currentTime
        }));
        depositor.isActive = true;
    }

    function get_usdc_contract () public view returns (IERC20) {
        return usdc_contract;
    }

    function getPoolBalance () public view returns (uint256) {
        return poolBalance;
    }

    

    function depositor_withdraw_principal (address depositor_address, uint256 amount) external onlyDepositor (depositor_address) {
        Depositor storage depositor = depositors[msg.sender];
        require(depositor.totalAmount >= amount, "Insufficient balance");
        require (usdc_contract.balanceOf(address(this)) >= amount, "Insufficient pool balance");

        uint256 totalWithdrawable = 0;
        for (uint256 i = 0; i < depositor.deposits.length; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                totalWithdrawable += record.amount;
            }
        }

        require(totalWithdrawable >= amount, "Cannot withdraw locked funds");

        // Transfer USDC back to the depositor
        bool success = usdc_contract.transfer(depositor_address, amount);
        require(success, "USDC transfer failed");

        // Update the depositor's total amount
        depositor.totalAmount -= amount;
        poolBalance -= amount;
        // Record the withdrawal
        depositor.principalWithdrawalRecords.push(PrincipalWithdrawalRecord({
            amountWithdrawn: amount,
            withdrawTime: block.timestamp
        }));
        emit DepositorPrincipalWithDrawalDone(address(this), depositor_address, totalWithdrawable, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }

    function calculate_depositor_interest_income (address depositor_address) 
                public returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[depositor_address];
        require(depositor.isActive, "Depositor not active");

        for (uint256 i = 0; i < depositor.deposits.length; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                uint256 timeDelta = currentTime - record.lastInterestWithdrawTimeForRecord;  // interest is calculated since last withdrawal
                uint256 interest = (record.amount * params.getBaseInterestRate() * timeDelta) / (365 days * 100);
                totalInterestIncome += interest;
                record.lastInterestWithdrawTimeForRecord = currentTime;
            }
        }
        return totalInterestIncome;
    }

        function preview_depositor_interest_income  (address depositor_address) 
                public view returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[depositor_address];
        require(depositor.isActive, "Depositor not active");

        for (uint256 i = 0; i < depositor.deposits.length; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                uint256 timeDelta = currentTime - record.lastInterestWithdrawTimeForRecord;  // interest is calculated since last withdrawal
                uint256 interest = (record.amount * params.getBaseInterestRate() * timeDelta) / (365 days * 100);
                totalInterestIncome += interest;
            }
        }
        return totalInterestIncome;
    }

    function depositor_withdraw_interest (address depositor_address, uint256 amount) public onlyDepositor (depositor_address) {
        Depositor storage depositor = depositors[msg.sender];
        uint256 totalInterestIncome = calculate_depositor_interest_income (depositor_address);
        require(totalInterestIncome >= amount, "Insufficient interest income");
        require (usdc_contract.balanceOf(address(this)) >= amount, "Insufficient pool balance");
        // Transfer USDC back to the depositor
        bool success = usdc_contract.transfer(depositor_address, amount);
        require(success, "USDC transfer failed");
        poolBalance -= amount;
        // Record the interest withdrawal
        uint256 currentTime = block.timestamp;
        depositor.interestWithdrawalRecords.push(InterestWithdrawalRecord({
            amountWithdrawn: amount,
            withdrawTime: currentTime
        }));
        emit DepositorInterestWithDrawalDone (address(this), depositor_address, totalInterestIncome, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }
}