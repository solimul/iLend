//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {NetworkConfig} from "./NetworkConfig.sol";

contract DepositPool {
    event DepositDone(address indexed depositor, address indexed depositedTo, uint256 amount, uint256 poolBalance, uint256 timestamp);
    address public owner;
    IERC20 public immutable usdc_contract;
    uint256 public poolBalance;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        NetworkConfig config = new NetworkConfig();
        usdc_contract = IERC20(config.getUSDCContract());
        poolBalance = 0;
    }

    function deposit_usdc (address depositor, uint256 amount) public returns (bool) {
        bool success = usdc_contract.transferFrom(depositor, address(this), amount);
        if (!success)
            return false;
        require (success, "Transfer failed");
        poolBalance += amount;
        emit DepositDone (depositor, address (this), amount, poolBalance,  block.timestamp);
        return true;
    }
}