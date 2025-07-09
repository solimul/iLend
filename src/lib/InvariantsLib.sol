// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

library InvariantsLib {
    function postDepositInvariantHolds (uint256 _oldBalance,
    uint256 _incomingAmount, 
    uint256 _currentBalance) 
    internal 
    pure 
    returns (bool){
        return _oldBalance + _incomingAmount >= _currentBalance;
    }

    function postStateUpdateInvariantEquality (uint256 _expected, 
    uint256 _actual) 
    internal 
    pure
    returns (bool){
        return _expected >= _actual;
    }
}
