//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {NetworkConfig} from "./NetworkConfig.sol";

contract DepositPool {
    address public owner;
    IERC20 public usdc_contrcact;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        NetworkConfig config = new NetworkConfig();
        usdc_contrcact = IERC20(config.getUSDCContract());
    }

    function deposit_usdc (address depositor, uint256 amount) public {
        require(usdc_contrcact.transferFrom(depositor, address(this), amount), "Transfer failed");
    }
}