//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Script} from "../../lib/forge-std/src/Script.sol";

contract Transaction {

    mapping (string => IERC20) tokenMapping;
    string constant USDC = "USDC";
    string constant ETH = "ETH";
    constructor (address _usdcAddress, address _ethAddress) {
        tokenMapping [USDC] = IERC20 (_usdcAddress);
        tokenMapping [ETH] = IERC20 (_ethAddress);
    }


    modifier has_enough_funds (IERC20 token, 
            address from, 
            uint256 amount)  {
        require (token.balanceOf (from) >= amount, "Not enought funds to transfer from");
        _;
    }

    function get_balance (string memory _tokenStr, 
        address _address) 
    public 
    view 
    returns (uint256) {
        return tokenMapping [_tokenStr].balanceOf (_address);
    }

    function safe_transfer_from (string memory _tokenStr, 
        address from, 
        address to, 
        uint256 amount) 
    public 
    has_enough_funds (tokenMapping [_tokenStr], from, amount){
        IERC20 token = tokenMapping [_tokenStr];
        token.approve(msg.sender, amount);
        require (token.transferFrom (from, to, amount), "safe-transfer-From failed.");
    }

    function safe_transfer_to (string memory _tokenStr, 
        address from, 
        address to, 
        uint256 amount) 
    public 
    has_enough_funds (tokenMapping [_tokenStr], from, amount){
        require (tokenMapping [_tokenStr].transferFrom (from, to, amount), "safe-transfer failed.");
    }
}