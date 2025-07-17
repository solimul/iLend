//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
library TransactionLib {

    modifier has_enough_funds (IERC20 token, 
            address from, 
            uint256 amount)  {
        require (token.balanceOf (from) >= amount, "Not enought funds to transfer from");
        _;
    }

    function get_balance (IERC20 token, 
        address _address) 
    public 
    view 
    returns (uint256) {
        return token.balanceOf (_address);
    }

    function check_approval_and_safe_transfer (IERC20 token, 
        address from, 
        address to, 
        uint256 amount) 
    internal 
    has_enough_funds (token, from, amount)
    returns (bool) {
        require(
            token.allowance(from, address(this)) >= amount,
            "TOKEN: allowance too low"
        );
        require(token.transferFrom(from, to, amount), "TOKEN: transferFrom failed");
        return true;
    }

    function safe_transfer (IERC20 token, 
        address from, 
        address to, 
        uint256 amount) 
    internal 
    has_enough_funds (token, from, amount)
    returns (bool){
        bool success = token.transferFrom (from, to, amount);
        require (success, "safe-transfer failed.");
        return success;
    }
}