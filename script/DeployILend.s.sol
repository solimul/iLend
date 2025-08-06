// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PricefeedManagerLib} from "../src/lib/PricefeedManagerLib.sol";
import {NetworkConfigLib} from "../src/lib/NetworkConfigLib.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Borrow module
import "../src/borrow/Borrow.sol";

// Collateral module
import "../src/collateral/Collateral.sol";

// Deposit module
import "../src/deposit/Deposit.sol";

// Liquidation module
import "../src/liquidation/LiquidationEngine.sol";
import "../src/liquidation/LiquidationRegistry.sol";
import "../src/liquidation/Monitor.sol";

// Misc module
import "../src/misc/Params.sol";

// Repayment module
import "../src/repayment/Payback.sol";

// Treasury module
import "../src/treasury/Treasury.sol";

// Shared interface
import {iLend} from "../src/ILend.sol";

import {RevertLib} from "../src/lib/RevertLib.sol";
import {PricefeedManagerLib} from "../src/lib/PricefeedManagerLib.sol";
import {PriceConverterLib} from "../src/lib/PriceConverterLib.sol";
import {NetworkConfigLib} from "../src/lib/NetworkConfigLib.sol";

/**
 * + running in anvil
 *     forge script script/DeployILend.s.sol:DeployILend \
 *     --rpc-url http://localhost:8545 \
 *     --broadcast \
 *     --slow
 *   + running in sepolia
 *     forge script script/DeployILend.s.sol:DeployILend \
 *     --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY \
 *     --broadcast \
 *     --slow
 *
 *   + running in mainnet 
 *     forge script script/DeployILend.s.sol:DeployILend \
 *     --rpc-url https://mainnet.infura.io/v3/YOUR_INFURA_KEY \
 *     --broadcast \
 *     --slow
 */
contract DeployILend is Script {
    using RevertLib for uint256;
    using PriceConverterLib for uint256;
    using PricefeedManagerLib for AggregatorV3Interface;

    error UnsupportedNetwork();

    Borrow private borrow;
    Collateral private collateral;
    Deposit private deposit;
    LiquidationEngine private liquidationEngine;
    LiquidationRegistry private liquidationRegistry;
    Monitor private monitor;
    Params private params;
    Payback private payback;
    Treasury private treasury;
    iLend private lendProtocol;
    AggregatorV3Interface private priceFeed;
    address private usdcAddress;
    address private wrappedETHAddress;

    string constant MAINNET_PRIVATE_KEY = "MAINNET_PRIVATE_KEY";
    string constant SEPOLIA_PRIVATE_KEY = "SEPOLIA_PRIVATE_KEY";
    string constant ANVIL_PRIVATE_KEY = "ANVIL_PRIVATE_KEY";

    uint256 constant MAINNET_CHAIN_ID = 1;
    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ANVIL_CHAIN_ID = 31337;

    function get_private_key() internal view returns (uint256 deployerPrivateKey) {
        uint256 chainID = block.chainid;
        if (chainID == MAINNET_CHAIN_ID) {
            // Ethereum Mainnet
            deployerPrivateKey = vm.envUint("MAINNET_PRIVATE_KEY");
        } else if (chainID == SEPOLIA_CHAIN_ID) {
            deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        } else if (chainID == ANVIL_CHAIN_ID) {
            deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        } else {
            revert UnsupportedNetwork();
        }
    }

    function run() external {
        uint256 deployerPrivateKey = get_private_key();
        vm.startBroadcast(deployerPrivateKey);
        params = new Params(false, false, false);
        vm.label(address(params), "Params");
        set_params();

        priceFeed = AggregatorV3Interface(PricefeedManagerLib.get_price_feed_address());
        usdcAddress = NetworkConfigLib.get_usdc_contract_address();
        wrappedETHAddress = NetworkConfigLib.get_eth_contract_address();

        treasury = new Treasury();
        vm.label(address(treasury), "Treasury");

        address trAddress = address(treasury);
        address pAddress = address(params);
        address pfAddress = address(priceFeed);

        collateral = new Collateral(pAddress, pfAddress, wrappedETHAddress);
        vm.label(address(collateral), "Collateral");

        address colAddress = address(collateral);

        deposit = new Deposit(pAddress, usdcAddress, colAddress);
        vm.label(address(deposit), "Deposit");

        address depAddress = address(deposit);

        borrow = new Borrow(pAddress, pfAddress, depAddress, colAddress, usdcAddress);
        vm.label(address(borrow), "Borrow");
        address borrowAddress = address(borrow);

        payback = new Payback(borrowAddress, depAddress, trAddress, usdcAddress);
        vm.label(address(payback), "Payback");

        liquidationRegistry = new LiquidationRegistry();
        address liqRegAddress = address(liquidationRegistry);

        monitor = new Monitor(pAddress, pfAddress, colAddress, liqRegAddress);
        vm.label(address(monitor), "Monitor");

        liquidationEngine = new LiquidationEngine(liqRegAddress, colAddress, depAddress, usdcAddress);

        address paybackAddress = address(payback);
        address monitorAddress = address(monitor);
        address liqEngineAddress = address(liquidationEngine);

        lendProtocol = new iLend(
            pAddress,
            pfAddress,
            usdcAddress,
            wrappedETHAddress,
            trAddress,
            colAddress,
            depAddress,
            borrowAddress,
            paybackAddress,
            liqRegAddress,
            monitorAddress,
            liqEngineAddress,
            false
        );
        vm.label(address(lendProtocol), "iLend");
        console.log("Deployed Params at:", address(params));
        console.log("Deployed Treasury at:", address(treasury));
        console.log("Deployed Collateral at:", address(collateral));
        console.log("Deployed Deposit at:", address(deposit));
        console.log("Deployed Borrow at:", address(borrow));
        console.log("Deployed Payback at:", address(payback));
        console.log("Deployed LiquidationRegistry at:", address(liquidationRegistry));
        console.log("Deployed Monitor at:", address(monitor));
        console.log("Deployed LiquidationEngine at:", address(liquidationEngine));
        console.log("Deployed iLend (Facade Contract) at:", address(lendProtocol));
        register_caller_contracts();
        vm.stopBroadcast();
    }

    function set_params() internal {
        //params.set_deposit_pool_params (500e6);
        params.set_deposit_params(100e6, 100_000_0e6, 1, 1 days, 365 days);
        params.set_borrow_params(1000, 1000000, 50, 1 days, 365 days, 5, 20, 200, 50);
        params.set_liquidation_params(150, 10, 1000, 50000, 1000, 50000, 5, "percentage");
        params.set_oracle_params(address(this), 60 seconds, 18);
        params.set_collateral_params(address(this), 1e18, 1000e18, 75, true);
    }

    function register_caller_contracts() internal {
        params.register_caller_contracts(address(lendProtocol));
        treasury.register_caller_contracts(address(lendProtocol), address(payback));
        borrow.register_caller_contracts(address(lendProtocol));
        collateral.register_caller_contracts(address(lendProtocol));
        deposit.register_caller_contracts(address(lendProtocol), address(payback), address(borrow));
        payback.register_caller_contracts(address(lendProtocol));
        liquidationRegistry.register_caller_contracts(address(lendProtocol), address(monitor));
        liquidationEngine.register_caller_contracts(address(lendProtocol));
        monitor.register_caller_contracts(address(lendProtocol));
    }
}
