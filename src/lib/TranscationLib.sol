//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";
library TransactionLib {

    error InsufficientTokenBalance(address from, uint256 balance, uint256 required);
    error AllowanceTooLow(address owner, address spender, uint256 allowance, uint256 required);
    error TransferFromFailed(address from, address to, uint256 amount);

    modifier has_enough_funds (IERC20 token, 
            address from, 
            uint256 amount)  {
        uint256 balance = token.balanceOf(from);
        if (balance < amount) {
            revert InsufficientTokenBalance(from, balance, amount);
        }
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
        uint256 currentAllowance = token.allowance(from, address(this));
        if (currentAllowance < amount) {
            revert AllowanceTooLow(from, address(this), currentAllowance, amount);
        }

        bool success = token.transferFrom(from, to, amount);
        if (!success) {
            revert TransferFromFailed(from, to, amount);
        }

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