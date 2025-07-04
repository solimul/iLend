//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CollateralPool} from "./CollateralPool.sol";
import {Params} from "../misc/Params.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {Borrow} from "../borrow/Borrow.sol";
import {CollateralView, 
        CollateralWithdrawalRecord, 
        CollateralDepositRecord,
        CollateralDepositor,
        DepletedCollateral} from "../shared/SharedStructures.sol";
import {Transaction} from "../misc/Transcation.sol";
import {PriceConverter} from "../helper/PriceConverter.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";

contract Collateral is CollateralPool {

    using PriceConverter for AggregatorV3Interface;

    event CollateralDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 depositTime,
        uint256 totalCollateral,
        uint256 depositCounts
    );

    Params private params;
    Borrow private borrow;
    Transaction private transaction;
    AggregatorV3Interface private pricefeed;
  
    mapping (address => CollateralDepositor) private collateralDepositors;
    address [] private collateralDeposotorAddresses;

    constructor(Params _params, 
                address _priceFeedAddress, 
                address _tAddress) CollateralPool (_priceFeedAddress) {
        params = _params;
        transaction = Transaction (_tAddress);
        pricefeed = AggregatorV3Interface (_priceFeedAddress);
        //borrow = Borrower(_borrowerContractAddress);
    } 

    modifier deposit_check (uint256 amount) {
        require(amount >= params.get_min_collateral_amount (),string(
            abi.encodePacked(
            "Collateral deposit must be >= ",
            Strings.toString(params.get_min_collateral_amount())
            )));
        require(amount <= params.get_max_collateral_amount (),string(
            abi.encodePacked(
            "Collateral deposit must be <= ",
            Strings.toString(params.get_max_collateral_amount())
            )));
            _;
    }

    modifier only_active_depositor(address depositor) {
        require(collateralDepositors[depositor].isActive, "Not an active depositor");
        _;
    }
    modifier only_valid_deposit_Index(address depositor, uint256 depositIndex) {
        require(depositIndex < collateralDepositors[depositor].depositCounts, "Invalid deposit index");
        _;
    }

    function deposit_collateral (address depositor, uint256 amount) external deposit_check (amount) returns (bool)  {
        require(deposit_eth(depositor, amount), "Transfer failed");

        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        if (!collateralDepositor.isActive) { // new
            collateralDepositor.isActive = true;
            collateralDeposotorAddresses.push (depositor);
        }
        collateralDepositor.totalAmount += amount;
        CollateralDepositRecord memory newDeposit = CollateralDepositRecord({
            amount: amount,
            hasBorrowedAgainst: false, // Initially, the deposit has not been borrowed against
            l2b: params.getL2B(), // Assuming L2B is a parameter set in Params
            depositTime: block.timestamp
        });
        collateralDepositor.collateralDepositRecords [collateralDepositor.depositCounts] = newDeposit;
        collateralDepositor.depositCounts += 1;
        emit CollateralDeposited(depositor, amount, block.timestamp, collateralDepositor.totalAmount, collateralDepositor.depositCounts);

        return true;
    }

    function update_collateral_depositor(
        address depositor,
        uint256 depositIndex,
        bool hasBorrowedAgainst
    ) external 
            only_active_depositor(depositor) 
            only_valid_deposit_Index(depositor, depositIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        collateralDepositor.collateralDepositRecords[depositIndex].hasBorrowedAgainst = hasBorrowedAgainst;
    }

    function get_collateral_depositors_deposit_count(address depositor) external view 
        only_active_depositor(depositor) 
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.depositCounts;
    }

    function get_collateral_ETH_by_record (
        address depositor,
        uint256 recordIndex
    ) public view 
        only_active_depositor(depositor) 
        only_valid_deposit_Index(depositor, recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.collateralDepositRecords[recordIndex].amount;
    }

    function get_collateralL2B_by_record (
        address depositor,
        uint256 recordIndex
    ) external view 
        only_active_depositor(depositor) 
        only_valid_deposit_Index(depositor, recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return collateralDepositor.collateralDepositRecords[recordIndex].l2b;
    }

    function update_borrowed_against_collateral (
        address depositor,
        uint256 recordIndex,
        bool hasBorrowedAgainst
    ) external 
        only_active_depositor(depositor) 
        only_valid_deposit_Index(depositor, recordIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        collateralDepositor.collateralDepositRecords[recordIndex].hasBorrowedAgainst = hasBorrowedAgainst;
    }

    function is_collateral_available(
        address depositor,
        uint256 recordIndex
    ) external view 
            only_active_depositor(depositor) 
            only_valid_deposit_Index(depositor, recordIndex)  
            returns (bool)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        return !collateralDepositor.collateralDepositRecords[recordIndex].hasBorrowedAgainst;
    }    

    function get_collateral_depositor_info (
        address depositor
    ) public view returns (CollateralView [] memory) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        CollateralView [] memory collateralViews = new CollateralView[](collateralDepositor.depositCounts);
        for (uint256 i = 0; i < collateralDepositor.depositCounts; i++) {
            CollateralDepositRecord storage record = collateralDepositor.collateralDepositRecords[i];
            if (record.depositTime != 0) // exclude the deleted records
            {
                uint256 iPayable = borrow.get_interest_payable (depositor, i);
                uint256 protocolReward = borrow.get_protocol_reward(depositor, i);

                collateralViews[i] = CollateralView({
                    loanID: i,
                    depositAmount: record.amount,
                    depositDate: record.depositTime,
                    hasBorrowedAgainst: record.hasBorrowedAgainst,
                    rate: pricefeed.getPrice (),
                    l2b: record.l2b,
                    totalUSDCBorrowed: borrow.get_borrowed_amount (depositor, i),
                    totalCollateralDepost: collateralDepositor.totalAmount,
                    baseInterestRate: borrow.get_borrowed_interest_rate (depositor, i),
                    interstPayable: iPayable, 
                    protoclRewardByReserveFactor: protocolReward, // Placeholder, needs to be calculated based on reserve factor logic
                    reserveFactor: params.get_reserve_factor(),
                    totalPayable: iPayable + protocolReward // Placeholder, needs to be calculated based on total payable logic
                    });
            }
        }
        return collateralViews;
    }

    function get_depeleted_collaterals (address _depositor)
    external view returns (CollateralView [] memory depletedCollaterals){
        CollateralDepositor storage depositor = collateralDepositors[_depositor];
        uint256 n = depositor.depositCounts;
        CollateralView [] memory cViews = get_collateral_depositor_info (_depositor);
        uint256 cnt = 0;
        uint256 currentRate = pricefeed.getPrice();
        uint256 lqThreshold = params.getLiquidationThreshold ();

        for (uint256 i=0; i < n; i++){
            CollateralView memory record = cViews [i];
            bool depleted = (currentRate * 100 / record.rate) < lqThreshold;
            if (depleted)
                cnt += 1;
        }
        depletedCollaterals = new CollateralView [] (cnt);
        uint256 k = 0;

        for (uint256 i=0; i < n; i++){
            CollateralView memory record = cViews [i];
            bool isDepleted = (currentRate * 100 / record.rate) < lqThreshold;
            if (isDepleted)
               depletedCollaterals [k++] = record;
        }
        return depletedCollaterals;
    }

    function set_borrower_contract(address _borrowerContractAddress) external {
        require(_borrowerContractAddress != address(0), "Invalid borrower contract address");
        borrow = Borrow(_borrowerContractAddress);
    }

    function deleteCollateralRecord (address depositor, uint256 _collateralID) internal {
        CollateralDepositor storage collateralDepositor = collateralDepositors[depositor];
        delete collateralDepositor.collateralDepositRecords[_collateralID];
    }

    function unlock_collateral (address _cDepositorAddress, uint256 _collateralID) public {
        uint256 amount = get_collateral_ETH_by_record(_cDepositorAddress, _collateralID);
        transaction.safe_transfer_from (eth_contract, address (this), _cDepositorAddress, amount);
        deleteCollateralRecord (_cDepositorAddress, _collateralID);
    }

    function get_collateral_depositor_addresses ()
    public view 
    returns(address [] memory) {
        return collateralDeposotorAddresses;
    }
}