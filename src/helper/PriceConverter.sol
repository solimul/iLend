//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";

library PriceConverter {

    function getPrice(AggregatorV3Interface priceFeed) public view returns (uint256) {
    // We need the following:
    // 1. Chainlink ETH/USD price feed address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
    // 2. Chainlink AggregatorV3Interface ABI

        (, int256 price, , , ) = priceFeed.latestRoundData();
    
        // price: ETH price in USD with 8 decimal places
        return uint256(price * 1e10); // Converts to 18 decimal places (common for ERC20 tokens)
    }

   function ethToUSD(uint256 ethAmount,
                    AggregatorV3Interface priceFeed) public view returns (uint256) {
      uint256 ethPrice = getPrice(priceFeed); // ETH price in USD with 18 decimal places
      uint256 ethAmountInUSD = (ethPrice * ethAmount) / 1e18;
      return ethAmountInUSD;
   }

    function getVersion (AggregatorV3Interface priceFeed) public view returns(uint256) {
        return priceFeed.version();
    }

   
}