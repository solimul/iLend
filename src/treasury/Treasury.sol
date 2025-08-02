//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ProtocolRewardInfo, Fee, MiscFundRecievedInfo} from "../shared/SharedStructures.sol";
import {iLend} from "../ILend.sol";


contract Treasury {
    event NativeETHReceived (address indexed sender, uint256 amount);
    event WETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeETHWithdrawn(address indexed to, uint256 amount);
    event FeesDeposited(address indexed depositor, uint256 fees,  uint256 dateReceived);

    error OnlyTreasuryOwnerCanAccess (address user, address iTreasuryOwner);
    error TreasuryHasInsufficientBalance (uint256 requested, uint256 available);
    error OnlyOwnerCanAccessThisFunction (address sender, address owner);
    error OnlyPaybackContractCanAccessThisFunction (address sender, address paybackContractAddress);
    error OnlyILendContractCanAccessThisFunction (address sender, address facadeContractAddress);


    ProtocolRewardInfo [] sProtocolRewardRecords;
    Fee [] sDepositFees;


    
    address private facadeContractAddress;
    address private immutable iOwnerAddress;
    address private paybackContractAddress;


    modifier only_owner_contract (address _sender) {
        if (_sender != iOwnerAddress) {
            revert OnlyOwnerCanAccessThisFunction (_sender, iOwnerAddress);
        }
        _;
    }

    modifier only_facade_contract(address _sender) {
        if (_sender != facadeContractAddress) {
            revert OnlyILendContractCanAccessThisFunction (_sender, facadeContractAddress);
        }
        _;
    }

    modifier only_payback_contract (address _sender) {
        if (_sender != paybackContractAddress) {
            revert OnlyPaybackContractCanAccessThisFunction (_sender, paybackContractAddress);
        }
        _;
    }


    constructor () {
        iOwnerAddress = msg.sender;
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
    only_owner_contract (msg.sender) {
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
    only_owner_contract (msg.sender) {
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
    external 
    only_payback_contract (msg.sender)
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
        return iOwnerAddress;
    }

   function register_caller_contracts 
    (
        address _iLendAddress, 
        address _paybackAddress
    ) 
    external 
    only_owner_contract (msg.sender){
        facadeContractAddress = _iLendAddress;
        paybackContractAddress = _paybackAddress;
    }

    function update_fees_for_deposit 
    (
        address _depositor, 
        uint256 _fees    
    ) 
    external
    only_facade_contract (msg.sender) {
        sDepositFees.push 
        (
          Fee 
          (  
            {
                amount: _fees,
                provider: _depositor,
                dateReceived: block.timestamp
            }
          )
        );
        emit FeesDeposited (_depositor, _fees, block.timestamp);
    }
}
