//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DepositPool {
    event DepositDone(address indexed depositor, address indexed depositedTo, uint256 amount, uint256 poolBalance, uint256 timestamp);
  
    address public owner;
    IERC20 public immutable usdc_contract;
    uint256 public poolBalance;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor(address _owner, 
            address _usdcContractAddress) {
        owner = _owner;
        usdc_contract = IERC20 (_usdcContractAddress);
        poolBalance = 0;
    }

    function get_usdc_contract_address () external view returns (IERC20) {
        return usdc_contract;
    }
}