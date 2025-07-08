// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @dev Interface for the ERC20 standard as defined in the EIP.
 * IERC20 provides function signatures for common token operations 
 * like transfer, approve, and allowance, but does not implement any logic.
 * Used to interact with any compliant ERC20 token.
 */
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

library NetworkConfigLib {


    function get_usdc_contract_address () external returns (address) {
        if (block.chainid == 31337) { // test-net 
            return address(new MockERC20("Mock USDC", "mUSDC"));
        } else if (block.chainid == 11155111) {  // sepolia
            // https://sepolia.etherscan.io/token/0x1c7d4b196cb0c7b01d743fbc6116a902379c7238
            return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // sepolia USDC
        }else if (block.chainid == 1) {           // Ethereum mainnet USDC
            // https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
            return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else {
            revert("NetworkConfig: unsupported network");
        }
    }

    function get_eth_contract_address () external returns (address) {
        if (block.chainid == 31337) { // test-net 
            return address(new MockERC20("Mock ETH", "mETH"));
        } else if (block.chainid == 11155111) {  // sepolia
            //https://sepolia.etherscan.io/address/0xdd13E55209Fd76AfE204dBda4007C227904f0a81            
            return 0xdd13E55209Fd76AfE204dBda4007C227904f0a81; // sepolia weth
        }else if (block.chainid == 1) {           // Ethereum mainnet
            // https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
        } else {
            revert("NetworkConfig: unsupported network");
        }
    }
}