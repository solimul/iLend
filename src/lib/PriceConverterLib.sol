//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {console} from "../../lib/forge-std/src/Script.sol";


library PriceConverterLib {

    error EtherAmountOverflowInWEI(uint256 amount);
    error USDCAmountOverflowInWEI(uint256 amount);
    
    uint256 constant ETHER_IN_WEI = 1e18;
    uint256 constant USDC_IN_WEI = 1e6;
    function getPrice(AggregatorV3Interface priceFeed) public view returns (uint256) {
    // We need the following:
    // 1. Chainlink ETH/USD price feed address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
    // 2. Chainlink AggregatorV3Interface ABI

        (, int256 price, , , ) = priceFeed.latestRoundData();
        // price: ETH price in USD with 8 decimal places
        return uint256(price * 1e10); // Converts to 18 decimal places (common for ERC20 tokens)
    }

   function ethToUSD(uint256 ethAmount,
            AggregatorV3Interface priceFeed) 
    public 
    view 
    returns (uint256) {
      uint256 ethPrice = getPrice(priceFeed); // ETH price in USD with 18 decimal places
      uint256 ethAmountInUSD = (ethPrice * ethAmount) / 1e18;
      return ethAmountInUSD;
   }

    function ethToUSDWEI(uint256 ethAmountWEI, 
            AggregatorV3Interface priceFeed) 
    public 
    view 
    returns (uint256) {
      uint256 ethPriceUSDCWEI = getPrice(priceFeed); // ETH price in USD with 18 decimal places
      // ethAmountInUSD is the current ETH to USD conversion rate in non-formatted (non-wei) term
      uint256 amountInUSDC = (ethPriceUSDCWEI * ethAmountWEI) / 1e18; 
      uint256 amountUSDCInWEI = convertUSDCToWEI(amountInUSDC); // eth
      return amountUSDCInWEI;
   }

    function getVersion (AggregatorV3Interface priceFeed) public view returns(uint256) {
        return priceFeed.version();
    }

    function convertEtherToWEI (uint256 _amount) public pure returns (uint256) {
        if (_amount > type(uint256).max / ETHER_IN_WEI)
            revert EtherAmountOverflowInWEI (_amount);
        return _amount * ETHER_IN_WEI;
    }

    function convertUSDCToWEI (uint256 _amount) public pure returns (uint256) {
        if (_amount > type(uint256).max / USDC_IN_WEI)
            revert USDCAmountOverflowInWEI (_amount);
        return _amount * USDC_IN_WEI;
    }

    function convertWEIToETH (uint256 _amount) public pure returns (uint256) {
        return _amount / ETHER_IN_WEI;
    }

    function convertWEIToUSDC (uint256 _amount) public pure returns (uint256) {
        return _amount / USDC_IN_WEI;
    }

   
}