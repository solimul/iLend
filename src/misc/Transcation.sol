//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";

contract Transaction {
    modifier has_enough_funds (IERC20 token, address from, uint256 amount)  {
        require (token.balanceOf (from) >= amount, "Not enought funds to transfer from");
        _;
    }

    
    function safe_transfer_from (IERC20 token, address from, address to, uint256 amount) 
    public 
    has_enough_funds (token, from, amount){
        token.approve(msg.sender, amount);
        require (token.transferFrom (from, to, amount), "transferFrom failed.");
    }
}