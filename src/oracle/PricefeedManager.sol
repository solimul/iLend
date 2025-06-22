//SPDX-License-Idetifier:MIT
pragma solidity ^0.8.18;

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

import {Script} from "@forge-std/Script.sol";
import {MockV3Aggregator} from "../../mocks/Mockv3Aggregator.sol";

contract PricefeedManager is Script {
    // If we on a local anvil chain, we deploy the mock price-feed first
    // Oterwise, grab the existing address from the live network.

    struct NetworkConfig {
        address priceFeedAddress;
    }

    NetworkConfig private activeNetworkConfig;

    // handling magic numbers
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;


    constructor () {
        if (block.chainid == SEPOLIA_CHAIN_ID)
            activeNetworkConfig = getSepoliaEthConfig ();
        else if (block.chainid == MAINNET_CHAIN_ID)
            activeNetworkConfig = getMainnetEthConfig ();
        else
            activeNetworkConfig = getAnvilEthConfig ();

    }

    function getSepoliaEthConfig () public pure returns (NetworkConfig memory) {
        // price feed address
        NetworkConfig memory sepoliaConfig = NetworkConfig (
            {priceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306});
        return sepoliaConfig;
    }

    /* 
        📍 On a local network like Anvil:

        → Real Chainlink price feed contracts do not exist.
        → So, we deploy a **mock price feed** (e.g., MockV3Aggregator) to simulate it.

        🔧 getAnvilConfig() does two things:
            1️⃣ Deploys the mock price feed contract on the local Anvil chain.
            2️⃣ Returns its address so it can be used in your main contract (e.g., FundMe).

        ✅ This lets your contract run and be tested locally just like on a live network.
    */

    function getAnvilEthConfig () public returns (NetworkConfig memory) {

        if (activeNetworkConfig.priceFeedAddress != address (0))
            return activeNetworkConfig;
        // price feed address
        //vm.startBroadcast ();
        // deploying the mock contract
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator 
                        (DECIMALS, INITIAL_PRICE);
        //vm.stopBroadcast ();
        
        // creating the network config using the deployed MockPriceFeed
        NetworkConfig memory anvilConfig = NetworkConfig ({
            priceFeedAddress : address (mockPriceFeed) 
        });
        return anvilConfig; 
    }

    function getMainnetEthConfig () public pure returns (NetworkConfig memory) {
        // price feed address
        NetworkConfig memory ethConfig = NetworkConfig (
            // grab it from https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=6
            {priceFeedAddress: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419}); 
        return ethConfig;
    }

    function getActiveNetworkConfig () public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function get_priceFeed_address () public view returns (address) {
        return activeNetworkConfig.priceFeedAddress;
    }
    function getPriceFeedDecimals () public pure returns (uint8) {
        return DECIMALS;
    }
    function getPriceFeedInitialPrice () public pure returns (int256) {
        return INITIAL_PRICE;
    }

}