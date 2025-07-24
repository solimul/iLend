//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ProtocolRewardInfo, MiscFundRecievedInfo} from "../shared/SharedStructures.sol";
import {Transaction} from "../misc/Transcation.sol";

contract Treasury {
    event NativeETHReceived (address indexed sender, uint256 amount);
    event WETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeETHWithdrawn(address indexed to, uint256 amount);

    error OnlyTreasuryOwnerCanAccess (address user, address iTreasuryOwner);
    error TreasuryHasInsufficientBalance (uint256 requested, uint256 available);

    address public immutable iTreasuryOwner;
    ProtocolRewardInfo [] sProtocolRewardRecords;

    
    modifier only_owner 
    (
        address _user
    ){
        if (_user != iTreasuryOwner) {
            revert OnlyTreasuryOwnerCanAccess (_user, iTreasuryOwner);
        }
        _;
    }


    constructor (address _owner ) {
        iTreasuryOwner = _owner;
    }

    receive() external payable {
        emit NativeETHReceived (msg.sender, msg.value);
    }

    fallback() external payable {
        emit NativeETHReceived (msg.sender, msg.value);
    }

    function withdraw_wrapped_ETH
    (
        address payable _to, 
        uint256 _amount
    ) 
    external 
    only_owner (_to) {
        if (address(this).balance < _amount){
            revert TreasuryHasInsufficientBalance (_amount, address(this).balance);
        }
        _to.transfer(_amount);
        emit WETHWithdrawn(_to, _amount);
    }

    function withdraw_native_ETH
    (
        address payable to, 
        uint256 amount
    ) 
    external 
    only_owner (msg.sender) {
        require(address(this).balance >= amount, "Insufficient native ETH balance");
        to.transfer(amount);
        emit NativeETHWithdrawn(to, amount);
    }

    function update_protocol_reward_records 
    (
        uint256 _amount, 
        address _from, 
        uint256 _loanID
    ) 
    public 
    {
        sProtocolRewardRecords.push (ProtocolRewardInfo ({
            amount : _amount,
            borrowerAddress: _from,
            loanID: _loanID,
            dateReceived: block.timestamp
        }));
    }

    function get_wrapped_ETH_balance 
    (
        address token
    ) 
    external 
    view 
    returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function get_native_ETH_balance() external view returns (uint256) {
        return address(this).balance;
    }

    function get_treasury_address () external view returns (address) {
        return iTreasuryOwner;
    }
}
