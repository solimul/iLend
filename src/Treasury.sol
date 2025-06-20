//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ProtocolRewardInfo, MiscFundRecievedInfo} from "./shared/SharedStructures.sol";

contract Treasury {
    event ReceivedETH(address indexed sender, uint256 amount);
    event ERC20Received(address indexed token, address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    address public immutable treasuryOwner;
    ProtocolRewardInfo [] protocolRewardRecords;
    MiscFundRecievedInfo [] miscFundReceivedRecords;

    
    modifier onlyOwner (address user){
        require (user == treasuryOwner, "Only the treasury user can withdraw.");
        _;
    }

    modifier enoughBalance (address from, IERC20 token, uint256 amount) {
        require (token.balanceOf (address(this)) >= amount, "Insufficient funds to be recieved by treasury.");
        _;
    }

    constructor (address _owner)  {
        treasuryOwner = _owner;
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    function reciveERC20Deposit(IERC20 token, address from, uint256 amount) external enoughBalance (from, token, amount) {
        require(token.transferFrom(from, address(this), amount), "Transfer failed");
        emit ERC20Received(address(token), from, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner (to) {
        require(address(this).balance >= amount, "Insufficient ETH");
        to.transfer(amount);
        emit ETHWithdrawn(to, amount);
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner (to) {
        require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
        IERC20(token).transfer(to, amount);
        emit ERC20Withdrawn(token, to, amount);
    }

    function updateProtocolRewardRecord (uint256 amount, address from, uint256 loanID) public {
        protocolRewardRecords.push (ProtocolRewardInfo ({
            amount : amount,
            borrowerAddress: from,
            loanID: loanID,
            dateReceived: block.timestamp
        }));
    }

    function updateMiscRecievedRecord (uint256 amount, string memory context) public {
        miscFundReceivedRecords.push (MiscFundRecievedInfo ({
            amount : amount,
            context: context,
            dateReceived: block.timestamp
        }));
    }

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }


    function getTreasuryAddress() external view returns (address) {
        return treasuryOwner;
    }
}
