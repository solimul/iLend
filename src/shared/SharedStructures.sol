// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/** 
 * Depost structures
 * **/

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



/** 
 * Borrow structures
 * **/


struct RepaymentComponent {
    uint256 pAmount;
    uint256 iAmount;
    uint256 rAmount;
}

struct BorrowRecord {
    uint256 loanID;
    uint256 amount;
    uint256 borrowTime;
    uint256 interestRate;
    uint256 l2b; 
    Lender [] lenders;
}



struct BorrowerRecord {
    address borrowerAddress;
    uint256 totalBorrowed;
    mapping(uint256 => BorrowRecord) borrows; // Maps borrow index to BorrowRecord
    uint256 borrowCount; // To keep track of the number of borrows
}

/** 
 * Collateral structures
 * **/

struct CollateralWithdrawalRecord {
    uint256 amountWithdrawn;
    uint256 withdrawTime;
}

struct CollateralDepositRecord {
    uint256 amount;
    uint256 depositTime;
    uint256 l2b; // Assuming l2b is a value associated with the deposit
    bool hasBorrowedAgainst;
}

struct CollateralDepositor {
    uint256 totalAmount;
    mapping (uint256 => CollateralDepositRecord) collateralDepositRecords;
    CollateralWithdrawalRecord [] collateralWithdrawalRecord;
    bool isActive;
    uint256 depositCounts; // To keep track of the number of deposits
}

struct CollateralView {
    uint256 loanID;
    uint256 depositAmount;
    uint256 depositDate;
    bool hasBorrowedAgainst;
    uint256 rate;
    uint256 l2b;
    uint256 totalUSDCBorrowed;
    uint256 totalCollateralDepost;
    uint256 baseInterestRate;
    uint256 interstPayable;
    uint256 protoclRewardByReserveFactor;
    uint256 reserveFactor;
    uint256 totalPayable;
}

struct DepletedCollateral {
    address _depositor;
    uint256 _collateralID;
    uint256 currentL2B;
    uint256 currentPrice;
    uint256 availableCollateral;    
}
/** 
 * Lending and Interest Structres
 * **/

struct Lender {
   address lender;
   uint256 [] depositAccountIDs;
   uint256 totalLent;
}

struct InterestEarned {
    uint256 loanID;
    address from;
    uint256 interestReceived;
    uint256 dateReceived;
}

struct ProtocolRewardInfo {
    uint256 amount;
    address borrowerAddress;
    uint256 loanID;
    uint256 dateReceived;
}

struct MiscFundRecievedInfo {
    uint256 amount;
    string context;
    uint256 dateReceived;
}



