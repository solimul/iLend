//SPDX-License-Idetifier:MIT
pragma solidity 0.8.30;

/*
1. Deploy a mock price feed (local Anvil chain):
    → Local blockchains like Anvil don't have real Chainlink price feeds.
    → So, you deploy a mock contract (e.g., MockV3Aggregator) to simulate price data.
    → This lets your contract work and be testable in local environments.

2. Keep track of contract address across different chains:
    → The same contract will have different addresses on Sepolia, Mainnet, Anvil, etc.
    → You should store these addresses in a mapping, config file, or constants by chain ID.
    → This helps your code select the correct address based on the network it's running on.
*/ 

import {MockV3Aggregator} from "../../mocks/Mockv3Aggregator.sol";

library PricefeedManagerLib {

    // handling magic numbers
    uint8  constant DECIMALS = 8;
    int256 constant INITIAL_PRICE = 2000e8;

    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant MAINNET_CHAIN_ID = 1;
    uint256 constant ANVIL_CHAIN_ID = 31337;

    address constant SEPOLIA_ETH_PRICEFEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant MAINNET_ETH_PRICEFEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;


    function get_price_feed_address () internal returns (address) {
        if (block.chainid == SEPOLIA_CHAIN_ID)
            return get_sepolia_eth_price_feed ();
        else if (block.chainid == MAINNET_CHAIN_ID)
            return get_mainnet_eth_price_feed ();
        else if (block.chainid == ANVIL_CHAIN_ID)
            return get_anvil_eth_price_feed ();
        else 
            revert("PriceFeedManager: unsupported network");
    }

    function get_sepolia_eth_price_feed () private pure returns (address) {
        return SEPOLIA_ETH_PRICEFEED;
    }

    /* 
        📍 On a local network like Anvil:

        → Real Chainlink price feed contracts do not exist.
        → So, we deploy a **mock price feed** (e.g., MockV3Aggregator) to simulate it.

        🔧 get_anvil_eth_price_feed() does two things:
            1️⃣ Deploys the mock price feed contract on the local Anvil chain.
            2️⃣ Returns its address so it can be used in your main contract

        ✅ This lets your contract run and be tested locally just like on a live network.
    */

    function get_anvil_eth_price_feed () private returns (address) {

        // deploying the mock contract
        return address(new MockV3Aggregator(DECIMALS, INITIAL_PRICE)); 
    }

    function get_mainnet_eth_price_feed () private pure returns (address) {
        // grab it from https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=6
        return MAINNET_ETH_PRICEFEED;
    }
}