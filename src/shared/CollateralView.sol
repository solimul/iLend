// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

struct CollateralView {
    uint256 id;
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
