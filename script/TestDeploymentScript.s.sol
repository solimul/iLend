// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {Collateral} from "../src/Collateral.sol";

/** 
 * @title DeployCollateralManager
 * @notice This script deploys the CollateralManager contract on the Sepolia testnet.
 * @dev To run this script, ensure you have the Sepolia RPC URL and private key set in your environment variables.
 * @dev Example command to run the script:  
 * forge script script/TestDeploymentScript.s.sol:DeployCollateralManager --broadcast --rpc-url $SEPOLIA_RPC_URL -vvvv
 * **/

contract DeployCollateralManager is Script {
    // function run() external {
    //     // Load private key from .env
    //     uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");

    //     // Start broadcast once
    //     vm.startBroadcast(deployerPrivateKey);

    //     // Deploy contract
    //     new Collateral ();

    //     // End broadcast
    //     vm.stopBroadcast();
    // }
}
