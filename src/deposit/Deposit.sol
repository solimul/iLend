//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {iLend} from "../ILend.sol";

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
import {Collateral} from "../collateral/Collateral.sol";

/** 
 * @title Deposit Contract - handle usdc depostsits 
 * @author Md Solimul Chowdhury
 * @notice This contract allows users to deposit USDC into the iLend protocol,
 * @dev This is a core component of the iLend protocol
**/

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

    error DepositorBalanceTooLow(address depositor, uint256 balance, uint256 required);
    error PoolBalanceTooLow(uint256 poolBalance, uint256 required);

    error WithdrawalExceedsUnlockedFunds(uint256 available, uint256 requested);

    error USDCTokenTransferFailed();

    error USDCTokenTransferAmountMismatch(uint256 expected, uint256 actual);

    error DepositorNotActive(address depositor);

    error InsufficientInterestIncome(uint256 available, uint256 requested);
    // PoolBalanceTooLow already declared

    error USDCTokenTransferFailedSafeTransfer (address from, address to, uint256 amount);
    error USDCTokenTransferAmountMismatchParams (uint256 expected, uint256 actual);

    error InvalidRecipientAddress();
    error RecipientNotBorrower(address expected, address actual);
    error BorrowerNotCollateralDepositor(address borrower);
    error CollateralNotDeposited(address borrower, uint256 collateralID);

    error NotAnActiveDepositor(address depositor);

    error DepositTooSmall(uint256 provided, uint256 minimum);
    error DepositTooLarge(uint256 provided, uint256 maximum);
    error LockupPeriodTooShort(uint256 provided, uint256 minimum);
    error LockupPeriodTooLong(uint256 provided, uint256 maximum);



    Params private params;
    Transaction private transaction;
    Collateral private collateral;
    
    mapping (address => Depositor) private depositors;
    address[] private depositorAddresses;
    uint256 private depositorCounts;

    uint256 private totalAvailableToLend;

    iLend private facadeContract;


    /**
     * @notice Initializes the contract with default values
     * @dev Constructor runs only once on deployment
     */

    constructor(address _paramsAddress, 
            address _usdcContractAddress, 
            address _tAddress,
            address _collateralAddress) 
            DepositPool(msg.sender, _usdcContractAddress) {
        params = Params (_paramsAddress);
        depositorCounts = 0;
        transaction = Transaction (_tAddress);
        collateral = Collateral (_collateralAddress);
        // Initialize the contract if needed
    }

     /**
     * @notice this modifier checks if the depositor exists
     */
    
    modifier existingDepositor (address depositor_address) {
        if (!depositors[depositor_address].isActive) {
            revert NotAnActiveDepositor(depositor_address);
        }
        _;
    }

      /**
     * @notice this modifier checks if the deposit amount 
     * and lockup period are within the allowed limits
     */

    modifier deposit_check (uint256 amount, 
            uint256 lockupPeriod) {
        uint256 minDeposit = params.getMinDeposit();
        if (amount < minDeposit) {
            revert DepositTooSmall(amount, minDeposit);
        }

        uint256 maxDeposit = params.getMaxDeposit();
        if (amount > maxDeposit) {
            revert DepositTooLarge(amount, maxDeposit);
        }

        uint256 minLockup = params.getMinLockupPeriod();
        if (lockupPeriod < minLockup) {
            revert LockupPeriodTooShort(lockupPeriod, minLockup);
        }

        uint256 maxLockup = params.getMaxLockupPeriod();
        if (lockupPeriod > maxLockup) {
            revert LockupPeriodTooLong(lockupPeriod, maxLockup);
        }

        _;
    }


    /**
     * @notice this function returns the USDC contract address
     * @return IERC20 - the USDC contract address
     */

    function get_usdc_contract () public view returns (IERC20) {
        return usdc_contract;
    }

    /**
     * @notice this function returns the total amount available to lend
     * @return uint256 - the total amount available to lend
     */

    function get_pool_balance () public view returns (uint256) {
        return poolBalance;
    }


    /**
     * @notice this function returns the balance of the deposit pool
     * @return uint256 - returns usdc balance of this deposit pool
     */
    function get_deposit_balance () public view returns (uint256) {
        return (usdc_contract).balanceOf (address (this));
    }


    /**
     * @notice this function get_deposit_record returns the deposit record of a depositor
     * @return uint256 returns the deposit record of a depositor
     */
    function get_deposit_record (address _depositorAddress, uint256 id) internal 
            existingDepositor (_depositorAddress) view returns (DepositRecord storage) {
        Depositor storage depositor = depositors [_depositorAddress];
        DepositRecord storage record = depositor.deposits [id];   
        return record;
    }


    /**
     * @notice this function returns the total amount lent out by a depositor
     * @return uint256 - the total amount lent out by the depositor
     */
    function get_lentout_amount (address _depositorAddress, uint256 id) public  view returns (uint256) {
        DepositRecord storage record = get_deposit_record (_depositorAddress, id);
        return record.amount - record.availableToLend;
    }


    function get_usdc_balance () public view returns (uint256) {
        return usdc_contract.balanceOf(address(this));
    }


    function update_post_deposit (address _depositorAddress, 
            uint256 _amount, 
            uint256 _lockupPeriod) 
            public {
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

    function update_principal_payback_record 
        ( 
            address _depositorAddress, 
            uint256 _depositID
        ) 
    public {    
        DepositRecord storage record = get_deposit_record(_depositorAddress, _depositID);
        record.availableToLend += get_lentout_amount (_depositorAddress, _depositID);
    }

    function update_interest_payback_record (address _borrowerAddress, 
            uint256 _loanID, 
            address _depositorAddress, 
            uint256 _depositID, 
            uint256 _totalInterest, 
            uint256 _totalLent, 
            uint256 lentFromThisDepositAccount) 
            public 
            returns (uint256) {
        
        DepositRecord storage record = get_deposit_record(_depositorAddress, _depositID);
        uint256 interestShare = (lentFromThisDepositAccount * _totalInterest) / _totalLent;
        record.interestEarned.push (InterestEarned({
            from: _borrowerAddress,
            loanID: _loanID,
            interestReceived:  interestShare,
            dateReceived: block.timestamp
        }));
        return interestShare;
    }

    function update_lentout_amount 
    ( 
        uint256 _amount
    ) 
    public {
        poolBalance -= _amount;
        totalAvailableToLend -= _amount;
    }

    function update_principal_withdrawal (address _depositorAddress, 
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

    function update_interest_withdrawal (address _depositorAddress, 
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


    // function deposit_funds (address _depositor_address, 
    //         uint256 _amount, 
    //         uint256 _lockupPeriod) 
    //         external 
    //         deposit_check (_amount,_lockupPeriod) {
        
    //     //uint256 old = get_usdc_balance();
        
    //     // bool success = deposit_usdc (_depositor_address, _amount); // Call to DepositPool to handle USDC transfe
        
    //     // if (!success) 
    //     //     revert("Deposit failed: USDC transfer unsuccessful in deposit_funds ()");
        
    //     // uint256 current = get_usdc_balance();

    //     // require (current - old == _amount, "Deposit amount mismatch");
        
    //     update_post_deposit (_depositor_address, _amount, _lockupPeriod);
  
    // }


    function withdraw_deposit (address _depositorAddress, 
            uint256 amount) 
            external 
            existingDepositor (_depositorAddress) {
        Depositor storage depositor = depositors[msg.sender];
        if (depositor.totalAmount < amount) {
            revert DepositorBalanceTooLow(msg.sender, depositor.totalAmount, amount);
        }

        uint256 old = get_usdc_balance();
        if (old < amount) {
            revert PoolBalanceTooLow(old, amount);
        }


        uint256 totalWithdrawable = 0;
        for (uint256 i = 0; i < depositor.depositCounts; i++) {
            DepositRecord storage record = depositor.deposits[i];
            if (block.timestamp >= record.depositTime + record.lockupPeriod) {
                totalWithdrawable += record.amount;
            }
        }

        if (totalWithdrawable < amount) {
            revert WithdrawalExceedsUnlockedFunds(totalWithdrawable, amount);
        }

        // Update the depositor's total amount
        update_principal_withdrawal (_depositorAddress, amount);

        // Transfer USDC back to the depositor
        bool success = usdc_contract.transfer(_depositorAddress, amount);
        if (!success) {
            revert USDCTokenTransferFailed();
        }

        uint256 current = get_usdc_balance();
        if (current != old - amount) {
            revert USDCTokenTransferAmountMismatch(old - amount, current);
        }

        emit DepositorPrincipalWithDrawalDone(address(this), _depositorAddress, totalWithdrawable, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }

    function calculate_depositor_interest (address _depositorAddress) 
            public 
            returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[_depositorAddress];
        if (!depositor.isActive) {
            revert DepositorNotActive(msg.sender);
        }

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

    function preview_depositor_interest  (address _depositorAddress) 
            public 
            view 
            returns (uint256 totalInterestIncome) {
        uint256 currentTime = block.timestamp;
        Depositor storage depositor = depositors[_depositorAddress];
        if (!depositor.isActive) {
            revert DepositorNotActive(msg.sender);
        }

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

    function withdraw_interest (address _depositorAddress, 
            uint256 amount) 
            public 
            existingDepositor (_depositorAddress) {
        uint256 totalInterestIncome = calculate_depositor_interest (_depositorAddress);
        
        uint256 old = usdc_contract.balanceOf(address(this));
        
        if (totalInterestIncome < amount) {
            revert InsufficientInterestIncome(totalInterestIncome, amount);
        }

        if (old < amount) {
            revert PoolBalanceTooLow(old, amount);
        }

        
        update_interest_withdrawal(_depositorAddress, amount);
        // Transfer USDC back to the depositor
        bool success = transaction.safe_transfer("USDC", address(this), _depositorAddress, amount);
        if (!success) {
            revert USDCTokenTransferFailedSafeTransfer(address(this), _depositorAddress, amount);
        }

        uint256 current = usdc_contract.balanceOf(address(this));
        uint256 expected = old - amount;
        if (current != expected) {
            revert USDCTokenTransferAmountMismatch(expected, current);
        }

        
        //emit DepositorInterestWithDrawalDone (address(this), _depositorAddress, totalInterestIncome, amount, depositor.totalAmount, poolBalance, block.timestamp);
    }

   function match_update_lenders (uint256 _amount)
    external
    returns (Lender[] memory) {
        uint256 len = depositorAddresses.length;
        Lender[] memory tempLenders = new Lender[](len); 
        Lender memory lender;

        uint256 fund = 0;
        bool completed = false;
        uint256 matchedLendersCount = 0;

        for (uint256 i = 0; i < len; i++) {
            Depositor storage depositor = depositors[depositorAddresses[i]];
            uint256 nDeposits = 0;
            uint256 cnt = depositor.depositCounts;
            uint256[] memory tepmIDs = new uint256[](cnt);
            uint256 totalLent = 0;
            for (uint256 j = 0; j < cnt; j++) {
                // if (remaining == 0) {
                //     completed = true;
                //     break;
                // }

                DepositRecord storage dRecord = depositor.deposits[j];
                uint256 availableToLend = dRecord.availableToLend;
                if (availableToLend > 0) {
                    tepmIDs[nDeposits++] = j;
                    uint256 remaining = _amount- fund;

                    uint256 lentAmount = 
                        remaining > availableToLend
                        ? availableToLend
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

    function withdraw_to_borrower (
        IERC20 _token, 
        address _to, 
        uint256 _amount,
        address _borrower,
        uint256 _collateralID
    ) public returns (bool) { 
        if (_to == address(0)) {
            revert InvalidRecipientAddress();
        }

        if (_to != _borrower) {
            revert RecipientNotBorrower(_borrower, _to);
        }

        if (!collateral.is_existing_collateral_depositor(_borrower)) {
            revert BorrowerNotCollateralDepositor(_borrower);
        }

        if (!collateral.is_collateral_deposted(_borrower, _collateralID)) {
            revert CollateralNotDeposited(_borrower, _collateralID);
        }

        bool ok = _token.transfer(_to, _amount);
        return ok;
    }

    function set_facade_contract (iLend _iLend) external {
        facadeContract = _iLend;
    }

    /**uint256 totalAmount;
    mapping (uint256 => DepositRecord) deposits; // Maps deposit index to DepositRecord
    InterestWithdrawalRecord [] interestWithdrawalRecords;
    PrincipalWithdrawalRecord [] principalWithdrawalRecords;
    bool isActive;
    uint256 depositCounts; // To keep track of the number of deposits */

    function test_get_depositor_deposit_attributes 
    (
        address _depositor
    ) 
    public
    view
    returns (uint256, uint256, uint256, bool, uint256) {
        Depositor storage depositor = depositors[_depositor];
        if (!depositors[_depositor].isActive)
            return (0,0,0,false, 0);
        return (depositor.totalAmount, 
                depositor.interestWithdrawalRecords.length,
                depositor.principalWithdrawalRecords.length,
                depositor.isActive,
                depositor.depositCounts);
    }

    /** struct DepositRecord {
    uint256 amount;
    uint256 depositTime;
    uint256 lockupPeriod;
    uint256 lastInterestWithdrawTimeForRecord; // Time of the last interest withdrawal
    uint256 availableToLend;
    InterestEarned [] interestEarned;
}
    **/

    function test_get_depositor_deposit_record_attributes 
    (
        address _depositor,
        uint256 _recordID
    ) 
    public
    view
    returns (uint256, uint256, uint256, uint256 ) {
        Depositor storage depositor = depositors[_depositor];
        DepositRecord memory depositRecord = depositor.deposits [_recordID];
        if (!depositors[_depositor].isActive)
            return (0, 0, 0, 0);
        return (depositRecord.amount, 
                depositRecord.lockupPeriod,
                depositRecord.availableToLend,
                depositRecord.interestEarned.length);
    }

    

}