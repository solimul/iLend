// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {CollateralManager} from "../src/CollateralManager.sol";

contract DeployCollateralManager is Script {
    function run() external {
        // Load private key from .env
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");

        // Start broadcast once
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contract
        new CollateralManager();

        // End broadcast
        vm.stopBroadcast();
    }
}
