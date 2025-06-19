//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {Params} from "./Params.sol";
import {Deposit} from "./Deposit.sol";
import {Collateral} from "./Collateral.sol";
import {Borrower} from "./Borrower.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "../src/helper/PriceConverter.sol";
import {PricefeedManager} from "./oracle/PricefeedManager.sol";
import {CollateralView} from "./shared/SharedStructures.sol";
import {ProtocolReward} from "./ProtocolReward.sol";

contract iLend {
    Params public params;   
    address public owner;
    Deposit public depositContract;
    Collateral public collateralContract;
    Borrower public borrowerContract;
    ProtocolReward public protocolRewardContract;
    AggregatorV3Interface public priceFeed;

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
        PricefeedManager priceFeedManager = new PricefeedManager();
        priceFeed = AggregatorV3Interface(priceFeedManager.getPriceFeedAddress());
        // Dependency injection for contracts: Factory pattern
        // This allows for easier testing and contract upgrades
        // The Deposit, Collateral, and Borrower contracts are initialized with the Params and PriceFeed
        // contracts, allowing them to access the necessary parameters and price feed data.
        depositContract = new Deposit(params);
        collateralContract = new Collateral(params, address (priceFeed));
        borrowerContract = new Borrower(params, address(priceFeed), address (depositContract), address (collateralContract));
        protocolRewardContract = new ProtocolReward(depositContract.get_usdc_contract(), owner);
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


    function deposit_collateral_borrow () external payable {
        // Call the deposit function in the Deposit contract
        collateralContract.get_eth_contract ().approve(address (collateralContract), msg.value);
        collateralContract.deposit_collateral (msg.sender, msg.value);
        if (!borrowerContract.borrowerExists (msg.sender))
            borrowerContract.addNewBorrower (msg.sender, 0, 0, 0, 0);
        borrowerContract.lendForCollateral (msg.sender, collateralContract.getCollateralDepositorsDepositCount(msg.sender)-1);
        collateralContract.updateBorrowedAgainstCollateral (msg.sender, collateralContract.getCollateralDepositorsDepositCount(msg.sender)-1, true);
    }

    function view_my_collateral_borrow_info () external returns (CollateralView [] memory) {
        // Call the view function in the Collateral contract
        collateralContract.setBorrowerContract(address (borrowerContract));
        return collateralContract.getCollateralDepositorInfo(msg.sender);
    }

    function repay_loan_interest_withdraw_collateral (uint256 _loanID) external payable{
        borrowerContract.repay_loan_principal_interest_protocol_reward (msg.sender, _loanID, msg.value);
        //depositContract.receive_interest (msg.sender, msg.value);
        //protocolRewardContract.receive_protocol_reward (msg.sender, msg.value);
    }


}