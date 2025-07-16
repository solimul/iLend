//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {Params} from "../misc/Params.sol";
import {DepositPool} from "../deposit/DepositPool.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Lender, 
        InterestEarned, 
        PrincipalWithdrawalRecord,
        InterestWithdrawalRecord, 
        DepositRecord, 
        Depositor} 
        from "../shared/SharedStructures.sol";
import {Transaction} from "../misc/Transcation.sol";
import {InvariantsLib} from "../lib/InvariantsLib.sol";


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

    event LiquidationReceived(
        address indexed liquidator,
        uint256 usdcAmount,
        uint256 poolBalance,
        uint256 timestamp
    );

    Params private params;
    Transaction private transaction;

    
    mapping (address => Depositor) private depositors;
    address[] private depositorAddresses;
    uint256 private depositorCounts;

    uint256 private totalAvailableToLend;


    constructor(address _paramsAddress, 
            address _usdcContractAddress, 
            address _tAddress) 
            DepositPool(msg.sender, _usdcContractAddress) {
        params = Params (_paramsAddress);
        depositorCounts = 0;
        transaction = Transaction (_tAddress);
        // Initialize the contract if needed
    }
    
    modifier existingDepositor (address depositor_address) {
        require (depositors[depositor_address].isActive, "Not a depositor");
        _;
    }

    modifier deposit_check (uint256 amount, 
            uint256 lockupPeriod) {
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

    function get_usdc_contract () public view returns (IERC20) {
        return usdc_contract;
    }

    function get_pool_balance () public view returns (uint256) {
        return poolBalance;
    }

    function get_deposit_balance () public view returns (uint256) {
        return (usdc_contract).balanceOf (address (this));
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

    function get_usdc_balance () public view returns (uint256) {
        return usdc_contract.balanceOf(address(this));
    }


    function post_deposit_state_update (address _depositorAddress, 
            uint256 _amount, 
            uint256 _lockupPeriod) 
            private {
        Depositor storage depositor = depositors[_depositorAddress];
        depositor.totalAmount += _amount;
        uint256 currentTime = block.timestamp;

        DepositRecord storage record = depositor.deposits[depositor.depositCounts];
        record.amount = _amount;
        record.depositTime = currentTime;
        record.lockupPeriod = _lockupPeriod;
        record.lastInterestWithdrawTimeForRecord = currentTime; // Initialize to current time
        record.availableToLend = _amount;
        depositor.deposits[depositor.depositCounts] = record;



        depositor.isActive = true;
        if (depositor.depositCounts == 0) {
            // If this is the first deposit, add the depositor to the list
            depositorAddresses.push(_depositorAddress);
            depositorCounts++;
        }
        depositor.depositCounts += 1;

        totalAvailableToLend += _amount;
    }

    function pre_principal_withdrawal_state_update (address _depositorAddress, 
            uint256 amount) 
            private {
        Depositor storage depositor = depositors[_depositorAddress];
        depositor.totalAmount -= amount;
        poolBalance -= amount;
        // Record the withdrawal
        depositor.principalWithdrawalRecords.push(PrincipalWithdrawalRecord({
            amountWithdrawn: amount,
            withdrawTime: block.timestamp
        }));
    }

    function pre_interest_withdrawal_state_update (address _depositorAddress, 
            uint256 amount) 
            private {
        Depositor storage depositor = depositors[_depositorAddress];
        poolBalance -= amount;
        totalAvailableToLend -= amount;
        // Record the interest withdrawal
        uint256 currentTime = block.timestamp;
        depositor.interestWithdrawalRecords.push(InterestWithdrawalRecord({
            amountWithdrawn: amount,
            withdrawTime: currentTime
        }));

    }


    function deposit_liquidity (address _depositor_address, 
            uint256 _amount, 
            uint256 _lockupPeriod) 
            external 
            deposit_check (_amount,_lockupPeriod) {
        
        uint256 old = get_usdc_balance();
        
        bool success = deposit_usdc (_depositor_address, _amount); // Call to DepositPool to handle USDC transfe
        
        if (!success) 
            revert("Deposit failed: USDC transfer unsuccessful in deposit_funds ()");
        
        uint256 current = get_usdc_balance();

        require (current - old == _amount, "Deposit amount mismatch");
        
        post_deposit_state_update(_depositor_address, _amount, _lockupPeriod);
        emit DepositorPrincipalWithDrawalDone(
            address(this), 
            _depositor_address, 
            _amount, 
            _amount, 
            depositors[_depositor_address].totalAmount, 
            poolBalance, 
            block.timestamp
        );
    }


    function depositor_withdraw_principal (address _depositorAddress, 
            uint256 amount) 
            external 
            existingDepositor (_depositorAddress) {
        Depositor storage depositor = depositors[msg.sender];
        require(depositor.totalAmount >= amount, "Insufficient balance");
        uint256 old = get_usdc_balance();
        require (old >= amount, "Insufficient pool balance");

        uint256 totalWithdrawable = 0;
        for (uint256 i = 0; i < depositor.depositCounts; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                totalWithdrawable += record.amount;
            }
        }

        require(totalWithdrawable >= amount, "Cannot withdraw locked funds");

        // Update the depositor's total amount
        pre_principal_withdrawal_state_update (_depositorAddress, amount);

        // Transfer USDC back to the depositor
        bool success = usdc_contract.transfer(_depositorAddress, amount);
        require(success, "USDC transfer failed");

        uint256 current = get_usdc_balance();
        require (current == old - amount, "USDC transfer amount mismatch");

        emit DepositorPrincipalWithDrawalDone(address(this), _depositorAddress, totalWithdrawable, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }

    function calculate_depositor_interest_income (address _depositorAddress) 
            public 
            returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[_depositorAddress];
        require(depositor.isActive, "Depositor not active");

        for (uint256 i = 0; i < depositor.depositCounts; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                uint256 timeDelta = currentTime - record.lastInterestWithdrawTimeForRecord;  // interest is calculated since last withdrawal
                uint256 interest = (record.amount * params.get_base_interest_rate() * timeDelta) / (365 days * 100);
                totalInterestIncome += interest;
                record.lastInterestWithdrawTimeForRecord = currentTime;
            }
        }
        return totalInterestIncome;
    }

    function preview_depositor_interest_income  (address _depositorAddress) 
            public 
            view 
            returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[_depositorAddress];
        require(depositor.isActive, "Depositor not active");

        for (uint256 i = 0; i < depositor.depositCounts; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                uint256 timeDelta = currentTime - record.lastInterestWithdrawTimeForRecord;  // interest is calculated since last withdrawal
                uint256 interest = (record.amount * params.get_base_interest_rate() * timeDelta) / (365 days * 100);
                totalInterestIncome += interest;
            }
        }
        return totalInterestIncome;
    }

    function depositor_withdraw_interest (address _depositorAddress, 
            uint256 amount) 
            public 
            existingDepositor (_depositorAddress) {
        uint256 totalInterestIncome = calculate_depositor_interest_income (_depositorAddress);
        
        uint256 old = usdc_contract.balanceOf(address(this));
        
        require(totalInterestIncome >= amount, "Insufficient interest income");
        require (old >= amount, "Insufficient pool balance");
        
        pre_interest_withdrawal_state_update(_depositorAddress, amount);
        // Transfer USDC back to the depositor
        bool success = transaction.safe_transfer("USDC",address (this), _depositorAddress, amount);
        require(success, "USDC transfer failed");

        uint256 current = usdc_contract.balanceOf(address(this));
        require (current == old - amount, "USDC transfer amount mismatch");
        
        //emit DepositorInterestWithDrawalDone (address(this), _depositorAddress, totalInterestIncome, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }

   function find_and_update_matching_depositors(uint256 _amount)
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
                uint256 remaining = _amount - fund;

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

                    if (fund >= _amount) {
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


    function lend_to_borrower (address _borrower_address, uint256 _amount) external returns (Lender [] memory){
        uint256 old = get_usdc_balance();
        require( old >= _amount, "Insufficient pool balance");
        Lender [] memory lenders;
        lenders = find_and_update_matching_depositors (_amount);
        
        poolBalance -= _amount;
        totalAvailableToLend -= _amount;
        
        require(transaction.safe_transfer("USDC", address (this), _borrower_address, _amount), 
                    "USDC transfer failed");
        
        uint256 current = get_usdc_balance();
        require (current == old - _amount, "USDC transfer amount mismatch");
        
        emit WithdrawnToBorrower (_borrower_address, _amount, poolBalance, block.timestamp);
        return  lenders;
    }

    function add_repaid_principal (address _borrowerAddress, address _depositorAddress, uint256 id) public returns (uint256) {
        uint256 lentOutAmount = get_lentout_amount (_depositorAddress, id);
        uint256 old = get_usdc_balance();
        require (old >= lentOutAmount, "Borrower does not have enough USDC for principal repayment.");        
        DepositRecord storage record = get_deposit_record(_depositorAddress, id);
        record.availableToLend += lentOutAmount;
        require (transaction.approve_and_safe_transfer("USDC",_borrowerAddress, address (this), lentOutAmount), 
                    "Cannot receive from the Borrower");
        uint256 current = get_usdc_balance();
        require (current == old + lentOutAmount, "USDC transfer amount mismatch");
        return lentOutAmount;
    }

    function add_interest (address _borrowerAddress, 
            uint256 _loanID, 
            address _depositorAddress, 
            uint256 depositID, 
            uint256 totalInterest, 
            uint256 totalLent) 
            public 
            returns (uint256) {
        uint256 lentFromThisDepositAccount = get_lentout_amount (_depositorAddress, depositID);
        uint256 old = get_usdc_balance();
        require (old >= lentFromThisDepositAccount, "Borrower does not have enough USDC for interest repayment.");        
        
        DepositRecord storage record = get_deposit_record(_depositorAddress, depositID);
        uint256 interestShare = (lentFromThisDepositAccount * totalInterest) / totalLent;
        record.interestEarned.push (InterestEarned({
            from: _borrowerAddress,
            loanID: _loanID,
            interestReceived:  interestShare,
            dateReceived: block.timestamp
        }));

        require (transaction.approve_and_safe_transfer("USDC",_borrowerAddress, address (this), interestShare), 
                    "Cannot receive Interest for this deposit record from the Borrower");
        
        uint256 current = get_usdc_balance();
        require (current == old + interestShare, "USDC transfer amount mismatch");
        return interestShare;
    }

    function receive_liquidation 
    (
        address _liquidator,
        uint256 _usdcAmount
    ) public {
        uint256 old = get_usdc_balance();
        require (transaction.approve_and_safe_transfer("USDC", _liquidator, address (this), _usdcAmount), 
                    "USDC transfer failed");
        uint256 current = get_usdc_balance();
        require (current == old + _usdcAmount, "USDC transfer amount mismatch");
        emit LiquidationReceived(_liquidator, _usdcAmount, current, block.timestamp);
    }
}