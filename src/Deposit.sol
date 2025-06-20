//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Params} from "./Params.sol";
import {DepositPool} from "./DepositPool.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lender,InterestEarned} from "./shared/SharedStructures.sol";


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
        uint256 availableToLend;
        InterestEarned [] interestEarned;
    }

    struct Depositor {
        uint256 totalAmount;
        mapping (uint256 => DepositRecord) deposits; // Maps deposit index to DepositRecord
        InterestWithdrawalRecord [] interestWithdrawalRecords;
        PrincipalWithdrawalRecord [] principalWithdrawalRecords;
        bool isActive;
        uint256 depositCounts; // To keep track of the number of deposits
    }

 

 

    Params public params;

    
    mapping (address => Depositor) private depositors;
    address[] private depositorAddresses;
    uint256 depositorCounts;


    constructor(Params _params) DepositPool(msg.sender) {
        params = _params;
        depositorCounts = 0;
        // Initialize the contract if needed
    }
    
    modifier existingDepositor (address depositor_address) {
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

    // function getDepositorInfo(address depositor) external view returns (Depositor memory) {
    //     return depositors[depositor];
    // }


    function deposit_liquidity (address depositor_address, uint256 amount, uint256 lockupPeriod) 
                external depositCheck (amount,lockupPeriod) {
        bool success = deposit_usdc (depositor_address, amount); // Call to DepositPool to handle USDC transfe
        
        if (!success) 
            revert("Deposit failed: USDC transfer unsuccessful in deposit_funds ()");

        Depositor storage depositor = depositors[depositor_address];
        depositor.totalAmount += amount;
        uint256 currentTime = block.timestamp;

        DepositRecord storage record = depositor.deposits[depositor.depositCounts];
        record.amount = amount;
        record.depositTime = currentTime;
        record.lockupPeriod = lockupPeriod;
        record.lastInterestWithdrawTimeForRecord = currentTime; // Initialize to current time
        record.availableToLend = amount;
        depositor.deposits[depositor.depositCounts] = record;



        depositor.isActive = true;
        if (depositor.depositCounts == 0) {
            // If this is the first deposit, add the depositor to the list
            depositorAddresses.push(depositor_address);
            depositorCounts++;
        }
        depositor.depositCounts += 1;
    }

    function get_usdc_contract () public view returns (IERC20) {
        return usdc_contract;
    }

    function getPoolBalance () public view returns (uint256) {
        return poolBalance;
    }



    function depositor_withdraw_principal (address depositor_address, uint256 amount) external existingDepositor (depositor_address) {
        Depositor storage depositor = depositors[msg.sender];
        require(depositor.totalAmount >= amount, "Insufficient balance");
        require (usdc_contract.balanceOf(address(this)) >= amount, "Insufficient pool balance");

        uint256 totalWithdrawable = 0;
        for (uint256 i = 0; i < depositor.depositCounts; i++) {
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

        for (uint256 i = 0; i < depositor.depositCounts; i++) {
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

        for (uint256 i = 0; i < depositor.depositCounts; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                uint256 timeDelta = currentTime - record.lastInterestWithdrawTimeForRecord;  // interest is calculated since last withdrawal
                uint256 interest = (record.amount * params.getBaseInterestRate() * timeDelta) / (365 days * 100);
                totalInterestIncome += interest;
            }
        }
        return totalInterestIncome;
    }

    function depositor_withdraw_interest (address depositor_address, uint256 amount) public existingDepositor (depositor_address) {
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

   function find_and_update_matching_depositors(uint256 amount)
    internal
    returns (Lender[] memory) {
        Lender[] memory tempLenders = new Lender[](depositorAddresses.length); 
        Lender memory lender;

        uint256 fund = 0;
        bool completed = false;
        uint256 matchedLendersCount = 0;

        for (uint256 i = 0; i < depositorAddresses.length; i++) {
            Depositor storage depositor = depositors[depositorAddresses[i]];
            uint256 nDeposits = 0;
            uint256[] memory tepmIDs = new uint256[](depositor.depositCounts);
            uint256 totalLent = 0;
            for (uint256 j = 0; j < depositor.depositCounts; j++) {
                DepositRecord storage dRecord = depositor.deposits[j];
                uint256 remaining = amount - fund;

                if (remaining == 0) {
                    completed = true;
                    break;
                }

                if (dRecord.availableToLend > 0) {
                    tepmIDs[nDeposits++] = j;

                    uint256 lentAmount = remaining > dRecord.availableToLend
                        ? dRecord.availableToLend
                        : remaining;

                    fund += lentAmount;
                    totalLent += lentAmount;
                    dRecord.availableToLend -= lentAmount;

                    if (fund >= amount) {
                        completed = true;
                        break;
                    }
                }
            }

            if (nDeposits > 0) {
                uint256[] memory ids = new uint256[](nDeposits);
                for (uint256 k = 0; k < nDeposits; k++) {
                    ids[k] = tepmIDs[k];
                }

                lender = Lender({
                    lender: depositorAddresses[i],
                    depositAccountIDs: ids,
                    totalLent:totalLent
                });

                tempLenders[matchedLendersCount++] = lender;
            }

            if (completed) {
                break;
            }
        }

        Lender[] memory lenders = new Lender[](matchedLendersCount);
        for (uint256 i = 0; i < matchedLendersCount; i++) {
            lenders[i] = tempLenders[i];
        }

        return lenders;
    }



    function lendToBorrower (address borrower_address, uint256 amount) external onlyOwner returns (Lender [] memory){
        require(usdc_contract.balanceOf(address(this)) >= amount, "Insufficient pool balance");
        Lender [] memory lenders;
        lenders = find_and_update_matching_depositors (amount);
        bool success = usdc_contract.transfer(borrower_address, amount);
        require(success, "USDC transfer failed");
        poolBalance -= amount;
        emit WithdrawnToBorrower (borrower_address, amount, poolBalance, block.timestamp);
        return  lenders;
    }

    function get_deposit_record (address _depositorAddress, uint256 id) internal 
            existingDepositor (_depositorAddress) view returns (DepositRecord storage) {
        Depositor storage depositor = depositors [_depositorAddress];
        DepositRecord storage record = depositor.deposits [id];   
        return record;
    }

    function get_lentout_amount (address _depositorAddress, uint256 id) internal  view returns (uint256) {
        DepositRecord storage record = get_deposit_record (_depositorAddress, id);
        return record.amount - record.availableToLend;
    }

    function receive_repayment_lentout_principal (address _borrowerAddress, address _depositorAddress, uint256 id) public returns (uint256) {
        uint256 lentOutAmount = get_lentout_amount (_depositorAddress, id);
        require (usdc_contract.balanceOf(address(_borrowerAddress)) >= lentOutAmount, "Borrower does not have enough USDC for principal repayment.");        
        DepositRecord storage record = get_deposit_record(_depositorAddress, id);
        require (usdc_contract.transferFrom (_borrowerAddress, address (this), lentOutAmount), "Cannot receive from the Borrower");
        record.availableToLend += lentOutAmount;
        return lentOutAmount;
    }

    function receive_interest_for_lender_deposit_record (address _borrowerAddress, address _depositorAddress, uint256 depositID, uint256 totalInterest, uint256 totalLent ) public returns (uint256) {
        uint256 lentFromThisDepositAccount = get_lentout_amount (_depositorAddress, depositID);
        require (usdc_contract.balanceOf(address(_borrowerAddress)) >= lentFromThisDepositAccount, "Borrower does not have enough USDC for interest repayment.");        
        DepositRecord storage record = get_deposit_record(_depositorAddress, depositID);
        uint256 interestShare = (lentFromThisDepositAccount * totalInterest) / totalLent;
        record.interestEarned.push (InterestEarned({
            from: _borrowerAddress,
            interestReceived:  interestShare,
            dateReceived: block.timestamp
        }));
        require (usdc_contract.transferFrom (_borrowerAddress, address (this), lentFromThisDepositAccount), "Cannot receive Interest for this deposit record from the Borrower");
        return interestShare;
    }
}