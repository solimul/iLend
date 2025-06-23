//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./misc/Params.sol";
import {Deposit} from "./deposit/Deposit.sol";
import {Collateral} from "./collateral/Collateral.sol";
import {Borrow} from "./borrow/Borrow.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./helper/PriceConverter.sol";
import {PricefeedManager} from "./oracle/PricefeedManager.sol";
import {CollateralView} from "./shared/SharedStructures.sol";
import {Treasury} from "./treasury/Treasury.sol";
import {NetworkConfig} from "./misc/NetworkConfig.sol";
import {Payback} from "./repayment/Payback.sol";
import {Transaction} from "./misc/Transcation.sol";

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
 

contract iLend {
    Params private params;   
    address private owner;
    Deposit private deposit;
    Collateral private collateral;
    Borrow private borrow;
    Treasury private treasury;
    Payback private payback;
    Transaction private transaction;
    AggregatorV3Interface private priceFeed;
    IERC20 private usdcContract;
    
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
        transaction = new Transaction ();
        params.initialize (false, false, false);
        set_params();
        PricefeedManager priceFeedManager = new PricefeedManager();
        priceFeed = AggregatorV3Interface(priceFeedManager.get_priceFeed_address());
        NetworkConfig config = new NetworkConfig();
        usdcContract = IERC20(config.get_usdc_contract_address());
        treasury = new Treasury (msg.sender, address (transaction));
        // Dependency injection for contracts: Factory pattern
        // This allows for easier testing and contract upgrades
        // The Deposit, Collateral, and Borrower contracts are initialized with the Params and PriceFeed
        // contracts, allowing them to access the necessary parameters and price feed data.
        deposit = new Deposit(params, usdcContract,  address (transaction));
        collateral = new Collateral(params, address (priceFeed),  address (transaction));
        borrow = new Borrow(params, 
                    address(priceFeed), 
                    address (deposit), 
                    address (collateral), 
                    usdcContract, 
                    address (transaction));
        payback = new Payback (address (borrow), 
                              address (deposit), 
                              address (treasury), 
                              address (usdcContract),
                              address (transaction));
    }

    function set_params() internal {
        // Set initial parameters
        params.set_deposit_params (1000, 1000000, 50, 1 days, 365 days);
        params.set_borrow_params (1000, 1000000, 50, 1 days, 365 days, 5, 20, 200, 50);
        params.set_liquidation_params (150, 10, 1000, 50000, 1000, 50000, 5, "percentage");
        params.set_oracle_params (address(this), 60 seconds, 18);
        params.set_collateral_params (address(this), 1000, 1000000, 75, true);
    }

    function deposit_liquidity (uint256 lockupPeriod) external payable{
        // Call the deposit function in the Deposit contract
        deposit.get_usdc_contract().approve(address (deposit), msg.value);
        deposit.deposit_liquidity (msg.sender, msg.value, lockupPeriod);
    }

    function withdraw_deposited_principal (uint256 amount) external {
        // Call the withdraw function in the Deposit contract
        deposit.depositor_withdraw_principal (msg.sender, amount);
    }

    function withdraw_deposited_interest (uint256 amount) external {
        // Call the withdraw interest function in the Deposit contract
        deposit.depositor_withdraw_interest(msg.sender, amount);
    }


    function deposit_collateral_borrow () external payable {
        // Call the deposit function in the Deposit contract
        collateral.get_eth_contract ().approve(address (collateral), msg.value);
        collateral.deposit_collateral (msg.sender, msg.value);
        if (!borrow.borrower_exists (msg.sender))
            borrow.add_new_borrower (msg.sender, 0, 0, 0, 0);
        borrow.lend_for_collateral (msg.sender, collateral.get_collateral_depositors_deposit_count(msg.sender)-1);
        collateral.update_borrowed_against_collateral (msg.sender, collateral.get_collateral_depositors_deposit_count(msg.sender)-1, true);
    }

    function get_my_collateral_info () external returns (CollateralView [] memory) {
        // Call the view function in the Collateral contract
        collateral.set_borrower_contract(address (borrow));
        return collateral.get_collateral_depositor_info(msg.sender);
    }

    function close_loan (uint256 _loanID) external payable {
        payback.process_repayment (msg.sender, _loanID, msg.value);
        collateral.unlock_collateral (msg.sender, _loanID);

    }
}