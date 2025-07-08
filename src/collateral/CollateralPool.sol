//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PricefeedManager} from "../oracle/PricefeedManager.sol";
import {PriceConverter} from "../helper/PriceConverter.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {console} from "@forge-std/console.sol"; // For debugging purposes, remove in production

contract CollateralPool {

    event CollateralDepositDone(
        address indexed depositor,
        address indexed depositedTo,
        uint256 amount,
        uint256 poolBalance,
        uint256 timestamp
    );
    // This contract serves as a base for collateral management
    // It can be extended by other contracts to implement specific collateral logic
    using PriceConverter for uint256; 
    AggregatorV3Interface private priceFeed;  
    PricefeedManager priceFeedManager;
    address public owner;
    IERC20 public immutable eth_contract;
    uint256 public poolBalance;

    



    constructor(address _priceFeedAddress, address _ethContractAddress) {
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        eth_contract = IERC20(_ethContractAddress);
    }

    function deposit_eth (address depositor, uint256 amount) public returns (bool) {
        bool success = eth_contract.transferFrom(depositor, address(this), amount);
        if (!success)
            return false;
        require (success, "Transfer failed");
        poolBalance += amount;
        emit CollateralDepositDone (depositor, address (this), amount, poolBalance,  block.timestamp);
        return true;
    }

    function getColleteralPoolAddress () external view returns (address) {
        return address(this);
    }
    function get_priceFeed_address() external view returns (address) {
        return address(priceFeed);
    }
    function getPriceFeedManagerAddress() external view returns (address) {
        return address(priceFeedManager);
    }

    function getPriceFeed () external view returns (AggregatorV3Interface) {
        return priceFeed;
    }

    function get_eth_contract () external view returns (IERC20) {
        return eth_contract;
    }
}