// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @dev Interface for the ERC20 standard as defined in the EIP.
 * IERC20 provides function signatures for common token operations 
 * like transfer, approve, and allowance, but does not implement any logic.
 * Used to interact with any compliant ERC20 token.
 */
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @dev SafeERC20 wraps around IERC20 functions and ensures safe execution.
 * It prevents issues with non-standard ERC20 tokens that do not return a boolean.
 * Commonly used to safely perform token transfers, approvals, etc.
 */
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract NetworkConfig {

    address private immutable i_owner;
    address private immutable i_usdc;
    address private immutable i_eth;
    MockERC20 private immutable i_mockerc20_usdc;
    MockERC20 private immutable i_mockerc20_eth;

    constructor () {
        i_owner = msg.sender;
        if (block.chainid == 31337) { // test-net 
            i_usdc = address(new MockERC20("Mock USDC", "mUSDC"));
            i_eth = address(new MockERC20("Mock ETH", "mETH"));

        } else if (block.chainid == 11155111) {  // sepolia
            i_usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 ; // USDC
            i_eth = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81; // WETH
            /** 
             * Token	Faucet
                    USDC	https://sepoliafaucet.com/ or from Aave/Gelato testnet UI
                    WETH	Chainlink Sepolia Faucet
             * **/
        }
    }

    function getOwner () external view returns (address) {
        return i_owner;
    }

    function getUSDCContract () external view returns (address) {
        return i_usdc;
    }

    function getETHContract () external view returns (address) {
        return i_eth;
    }
    // Define the mainnet and testnet addresses for USDC and WETH
}