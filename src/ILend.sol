//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./Params.sol";
import {Deposit} from "./Deposit.sol";
import {Collateral} from "./Collateral.sol";

contract iLend {
    Params public params;   
    address public owner;
    Deposit public depositContract;
    Collateral public collateralContract;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // modifier token_type_check (string memory token, string memory expectedToken) {
    //     string memory message = keccak256(abi.encodePacked("Sent ", token, ", expected ", expectedToken));
    //     require(keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked(expectedToken)), message);
    //     _;
    // }

    constructor () {
        owner = msg.sender;
        params = new Params(owner);
        params.initialize (false, false, false);
        setParams();
        depositContract = new Deposit(params);
        collateralContract = new Collateral(params);
    }

    function setParams() internal {
        // Set initial parameters
        params.setDepositParams(1000, 1000000, 50, 1 days, 365 days);
        params.setBorrowParams(1000, 1000000, 50, 1 days, 365 days, 5, 20, 200, 50);
        params.setLiquidationParams(150, 10, 1000, 50000, 1000, 50000, 5, "percentage");
        params.setOracleParams(address(this), 60 seconds, 18);
        params.setCollateralParams(address(this), 1000, 1000000, 75, true);
    }

    function deposit_liquidity (uint256 lockupPeriod) external payable{
        // Call the deposit function in the Deposit contract
        depositContract.get_usdc_contract().approve(address (depositContract), msg.value);
        depositContract.deposit_liquidity (msg.sender, msg.value, lockupPeriod);
    }

    function withdraw_deposited_principal (uint256 amount) external {
        // Call the withdraw function in the Deposit contract
        depositContract.depositor_withdraw_principal (msg.sender, amount);
    }

    function withdraw_deposited_interest (uint256 amount) external {
        // Call the withdraw interest function in the Deposit contract
        depositContract.depositor_withdraw_interest(msg.sender, amount);
    }


    function deposit_collateral () external payable {
        // Call the deposit function in the Deposit contract
        collateralContract.get_eth_contract ().approve(address (collateralContract), msg.value);
        collateralContract.deposit_collateral (msg.sender, msg.value);
    }


}