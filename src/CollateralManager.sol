//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PricefeedManager} from "./oracle/PricefeedManager.sol";
import {PriceConverter} from "./helper/PriceConverter.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {console} from "@forge-std/console.sol"; // For debugging purposes, remove in production

contract CollateralManager {
    using PriceConverter for uint256; 
    AggregatorV3Interface private priceFeed;   
    constructor() {
        // Initialize the ConfigManager with the address of the deployed contract
        PricefeedManager pricefeedManager = new PricefeedManager();
        priceFeed = AggregatorV3Interface (pricefeedManager.getPriceFeedAddress ());  
        console.log ("====> Price: ",PriceConverter.getPrice(priceFeed) / 1e18); // Log the price in USD with 18 decimal places
    }
}