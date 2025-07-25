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
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {iLend} from "../ILend.sol";

import {LiquidationEngine} from "../liquidation/LiquidationEngine.sol";

contract Collateral is CollateralPool {

    error NotARegisteredLiquidator(address caller);
    error CollateralAlreadyLiquidated(address borrower, uint256 loanID);
    error InvalidLiquidationEngineAddress();
    error CollateralDepositTooSmall(uint256 provided, uint256 minimum);
    error CollateralDepositTooLarge(uint256 provided, uint256 maximum);

    error NotAnActiveCollateralDepositor(address depositor);

    error InvalidCollateralDepositIndex(address depositor, uint256 index, uint256 maxIndex);
    error InvalidBorrowerContractAddress();


    using PriceConverter for AggregatorV3Interface;

    event CollateralDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 depositTime,
        uint256 totalCollateral,
        uint256 depositCounts
    );

    error INSUFFICIENT_BALANCE_IN_COLLATERAL(uint256 required, uint256 available);

    Params private params;
    Borrow private borrow;
    Transaction private transaction;
    LiquidationEngine private liquidationEngine;
    AggregatorV3Interface private pricefeed;
  
    mapping (address => CollateralDepositor) private collateralDepositors;
    address [] private collateralDeposotorAddresses;
    iLend private facadeContract;


    constructor(address _paramsAddress, 
                address _priceFeedAddress, 
                address _tAddress,
                address _ethContractAddress) CollateralPool (_priceFeedAddress, _ethContractAddress) {
        params = Params (_paramsAddress);
        transaction = Transaction (_tAddress);
        pricefeed = AggregatorV3Interface (_priceFeedAddress);
    } 

    modifier deposit_check(uint256 amount) {
        uint256 min = params.get_min_collateral_amount();
        uint256 max = params.get_max_collateral_amount();

        if (amount < min) {
            revert CollateralDepositTooSmall(amount, min);
        }

        if (amount > max) {
            revert CollateralDepositTooLarge(amount, max);
        }
        _;
    }

    modifier only_active_depositor(address _depositor) {
        if (!collateralDepositors[_depositor].isActive) {
            revert NotAnActiveCollateralDepositor(_depositor);
        }
        _;
    }

    modifier only_valid_deposit_Index(address _depositor, uint256 _depositIndex) {
        uint256 maxIndex = collateralDepositors[_depositor].depositCounts;
        if (_depositIndex >= maxIndex) {
            revert InvalidCollateralDepositIndex(_depositor, _depositIndex, maxIndex);
        }
        _;
    }


    function update_collateral_records (address _depositor, uint256 _amount) external deposit_check (_amount) returns (bool)  {
        //require(deposit_eth(_depositor, _amount), "Transfer failed");

        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        if (!collateralDepositor.isActive) { // new
            collateralDepositor.isActive = true;
            collateralDeposotorAddresses.push (_depositor);
        }
        collateralDepositor.totalAmount += _amount;
        CollateralDepositRecord memory newDeposit = CollateralDepositRecord({
            amount: _amount,
            hasBorrowedAgainst: false, // Initially, the deposit has not been borrowed against
            l2b: params.getL2B(), // Assuming L2B is a parameter set in Params
            depositTime: block.timestamp
        });
        collateralDepositor.collateralDepositRecords [collateralDepositor.depositCounts] = newDeposit;
        collateralDepositor.depositCounts += 1;
        emit CollateralDeposited(_depositor, _amount, block.timestamp, collateralDepositor.totalAmount, collateralDepositor.depositCounts);

        return true;
    }

    function update_collateral_depositor(
        address _depositor,
        uint256 _depositIndex,
        bool _hasBorrowedAgainst
    ) external 
            only_active_depositor(_depositor) 
            only_valid_deposit_Index(_depositor, _depositIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        collateralDepositor.collateralDepositRecords[_depositIndex].hasBorrowedAgainst = _hasBorrowedAgainst;
    }

    function get_collateral_deposit_count(address _depositor) 
        external 
        view 
        only_active_depositor(_depositor) 
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        return collateralDepositor.depositCounts;
    }

    function get_collateral_ETH_by_record (
        address _depositor,
        uint256 _recordIndex
    ) public view 
        only_active_depositor(_depositor) 
        only_valid_deposit_Index(_depositor, _recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        return collateralDepositor.collateralDepositRecords[_recordIndex].amount;
    }

    function get_collateralL2B_by_record (
        address _depositor,
        uint256 _recordIndex
    ) external view 
        only_active_depositor(_depositor) 
        only_valid_deposit_Index(_depositor, _recordIndex)  
    returns (uint256) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        return collateralDepositor.collateralDepositRecords[_recordIndex].l2b;
    }

    function update_borrowed_against_collateral (
        address _depositor,
        uint256 _recordIndex,
        bool _hasBorrowedAgainst
    ) external 
        only_active_depositor(_depositor) 
        only_valid_deposit_Index(_depositor, _recordIndex)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        collateralDepositor.collateralDepositRecords[_recordIndex].hasBorrowedAgainst = _hasBorrowedAgainst;
    }

    function is_collateral_available(
        address _depositor,
        uint256 _recordIndex
    ) external view 
            only_active_depositor(_depositor) 
            only_valid_deposit_Index(_depositor, _recordIndex)  
            returns (bool)  {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        return !collateralDepositor.collateralDepositRecords[_recordIndex].hasBorrowedAgainst;
    }    

    function get_collateral_depositor_info (address _depositor) 
            public 
            view 
            returns (CollateralView [] memory) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        CollateralView [] memory collateralViews = new CollateralView[](collateralDepositor.depositCounts);
        for (uint256 i = 0; i < collateralDepositor.depositCounts; i++) {
            CollateralDepositRecord storage record = collateralDepositor.collateralDepositRecords[i];
            if (record.depositTime != 0) // exclude the deleted records
            {
                uint256 iPayable = borrow.get_interest_payable (_depositor, i);
                uint256 protocolReward = borrow.get_protocol_reward(_depositor, i);

                collateralViews[i] = CollateralView({
                    loanID: i,
                    depositAmount: record.amount,
                    depositDate: record.depositTime,
                    hasBorrowedAgainst: record.hasBorrowedAgainst,
                    rate: pricefeed.getPrice (),
                    l2b: record.l2b,
                    totalUSDCBorrowed: borrow.get_borrowed_amount (_depositor, i),
                    totalCollateralDepost: collateralDepositor.totalAmount,
                    baseInterestRate: borrow.get_borrowed_interest_rate (_depositor, i),
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
            external 
            view 
            returns (CollateralView [] memory depletedCollaterals){
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

    function set_borrower_contract (address _borrowerContractAddress) external {
        if (_borrowerContractAddress == address(0)) {
            revert InvalidBorrowerContractAddress();
        }
        borrow = Borrow(_borrowerContractAddress);
    }

    function deleteCollateralRecord (address _depositor, 
        uint256 _collateralID) 
    internal {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_depositor];
        delete collateralDepositor.collateralDepositRecords[_collateralID];
    }

    function unlock_collateral 
    (
        IERC20 _token,
        address _cDepositorAddress, 
        uint256 _collateralID
    ) 
    public {
        uint256 amount = get_collateral_ETH_by_record(_cDepositorAddress, _collateralID);
        uint256 balance = _token.balanceOf(address(this));
        if (amount > balance) {
            revert INSUFFICIENT_BALANCE_IN_COLLATERAL (amount, balance);
        }
        _token.transfer(_cDepositorAddress, amount);
        deleteCollateralRecord (_cDepositorAddress, _collateralID);
    }

    function get_collateral_depositor_addresses ()
    public 
    view 
    returns(address [] memory) {
        return collateralDeposotorAddresses;
    }

    function withdraw_to_liquidator (
        IERC20 _token,
        address _liquidtor,
        uint256 _amount,
        address _borrower,
        uint256 _loanID 
    ) public returns (bool) {
       if (!liquidationEngine.is_a_liquidator(_liquidtor)) {
            revert NotARegisteredLiquidator(_liquidtor);
        }

        if (!liquidationEngine.yet_to_be_liquidated(_borrower, _loanID)) {
            revert CollateralAlreadyLiquidated(_borrower, _loanID);
        }
        bool ok = _token.transfer(_liquidtor, _amount);
        return ok;
    }

    function is_collateral_deposted 
    (
        address _borrower,
        uint256 _collateralID
    )
    public 
    returns (bool) {
        CollateralDepositor storage collateralDepositor = collateralDepositors[_borrower];
        return collateralDepositor.collateralDepositRecords[_collateralID].amount > 0;
    }

    function is_existing_collateral_depositor (
        address _depositor
    )
    public
    view
    returns (bool) {
        return collateralDepositors[_depositor].isActive;   
    }

    function set_liquidation_engine (address _liqEngineAddress) external {
        if (_liqEngineAddress == address(0)) {
            revert InvalidLiquidationEngineAddress();
        }
        liquidationEngine = LiquidationEngine(_liqEngineAddress);
    }   
    
    function set_facade_contract (iLend _iLend) external {
        facadeContract = _iLend;
    }
}