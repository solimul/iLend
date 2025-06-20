// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

struct CollateralView {
    uint256 loanID;
    uint256 depositAmount;
    uint256 depositDate;
    bool hasBorrowedAgainst;
    uint256 l2b;
    uint256 totalUSDCBorrowed;
    uint256 totalCollateralDepost;
    uint256 baseInterestRate;
    uint256 interstPayable;
    uint256 protoclRewardByReserveFactor;
    uint256 reserveFactor;
    uint256 totalPayable;
}

struct Lender {
   address lender;
   uint256 [] depositAccountIDs;
   uint256 totalLent;
}

struct InterestEarned {
    address from;
    uint256 interestReceived;
    uint256 dateReceived;
}
