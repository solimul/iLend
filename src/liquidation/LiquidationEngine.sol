// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;
import {LiquidationReadyCollateral} from "../shared/SharedStructures.sol";
import {LiquidationRegistry} from "../liquidation/LiquidationRegistry.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Liquidator, LiquidationRecord} from "../shared/SharedStructures.sol";

import {Transaction} from "../misc/Transcation.sol";

contract LiquidationEngine {

    event LiquidationCompleted(
        address indexed liquidator,
        address indexed borrower,
        uint256 loanID,
        uint256 usdcAmount,
        uint256 ethReceived,
        uint256 timeStamp
    );


    LiquidationRegistry private liqReg;
    Collateral private collateral;
    Deposit private deposit;
    Transaction private transaction;
    uint256 private constant HUNDRED = 100;

    address [] liquidatorsList;
    mapping (address => Liquidator) liquidatorsMap;

    constructor (address _liquidationRegistryAddress,
        address _collateralAddress,
        address _depositAddress,
        address _transactionAddress) {
        liqReg = LiquidationRegistry (_liquidationRegistryAddress);
        collateral = Collateral (_collateralAddress);
        deposit = Deposit (_depositAddress);
        transaction = Transaction (_transactionAddress);
    }

    function quote_liquidation (address _borrower, 
        uint256 _loanID) 
    public view returns 
    (
        uint256 shortFallUSDC, 
        uint256 ethToReceive
    ) {
        LiquidationReadyCollateral memory col = liqReg.get_liquidation_ready_collateral_information_for_the_borrower_and_loanID(_borrower, _loanID);
        shortFallUSDC = col.shortFallUSDC;
        uint256 bonus = HUNDRED + col.discountRate;
        uint256 usdcWithBonus = col.shortFallUSDC * bonus;
        ethToReceive  = usdcWithBonus / (col.currentRate*HUNDRED); 
        require (col.liquidableETH >= ethToReceive, "Not enough ETH to liquidate.");
    }

    function update_liquidation_records ( address _liquidator,
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount,
        uint256 _ethRecieved) 
    internal {
        Liquidator storage liquidatorInfo = liquidatorsMap [_liquidator];

        if (liquidatorInfo.liquidator  == address (0)) { // new liquidator
            liquidatorsList.push (_liquidator);
            liquidatorInfo.liquidator = _liquidator;
        }
        liquidatorInfo.totalLiquidatProvided += _usdcAmount;
        liquidatorInfo.totalDiscountedAssetReceived += _ethRecieved;
        LiquidationRecord memory liqRecord = LiquidationRecord ({
            liquidationUSDCAmount: _usdcAmount,
            discountedETHRecieved: _ethRecieved,
            liquidatedCollateral: liqReg.get_liquidation_ready_collateral_information_for_the_borrower_and_loanID(_borrower, _loanID),
            liquidInjectionDateTime: block.timestamp
        });
        liquidatorInfo.liquidationRecords.push (liqRecord);

        emit LiquidationCompleted (_liquidator, _borrower, _loanID, _usdcAmount, _ethRecieved, block.timestamp);
    }

    function inject_liquid_send_discounted_collateral ( address _liquidator,
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount) 
    public
    {
        (uint256 shortFallUSDC, uint256 ethToTransfer) = quote_liquidation (_borrower, _loanID);
        require (_usdcAmount >= shortFallUSDC, "sent USDC is less than the short fall.");
        require (_usdcAmount >= transaction.get_balance ("USDC",_liquidator), "Liquidator does not have enough balance");
        require (ethToTransfer < collateral.get_collateral_ETH_by_record (_borrower, _loanID), "Not enough ETH available for this collateral to be discounted");
        deposit.receive_liquidation (_liquidator, _usdcAmount);
        collateral.send_to_liquidator (_liquidator, ethToTransfer);
        update_liquidation_records (_liquidator,_borrower,_loanID,_usdcAmount, ethToTransfer);
    }
}