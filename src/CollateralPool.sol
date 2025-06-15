//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PricefeedManager} from "./oracle/PricefeedManager.sol";
import {PriceConverter} from "./helper/PriceConverter.sol";
import {NetworkConfig} from "./NetworkConfig.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {console} from "@forge-std/console.sol"; // For debugging purposes, remove in production

contract CollateralPool {
    // This contract serves as a base for collateral management
    // It can be extended by other contracts to implement specific collateral logic
    using PriceConverter for uint256; 
    AggregatorV3Interface private priceFeed;  
    PricefeedManager priceFeedManager;
    NetworkConfig config;
    address public owner;
    IERC20 public immutable eth_contract;



    constructor(address pricefeedManagerAddress) {
        priceFeedManager = PricefeedManager(pricefeedManagerAddress);
        priceFeed = AggregatorV3Interface(priceFeedManager.getPriceFeedAddress());
        config = new NetworkConfig();
        eth_contract = IERC20(config.getETHContract());
    }

    function getColleteralPoolAddress () external view returns (address) {
        return address(this);
    }
    function getPriceFeedAddress() external view returns (address) {
        return address(priceFeed);
    }
    function getPriceFeedManagerAddress() external view returns (address) {
        return address(priceFeedManager);
    }
    function getNetworkConfigAddress() external view returns (address) {
        return address(config);
    }

    
}