//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {KeeperCompatibleInterface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {PricefeedManager} from "../oracle/PricefeedManager.sol";
import {PriceConverter} from "../helper/PriceConverter.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {CollateralView} from "../shared/SharedStructures.sol";
import {Params} from "../misc/Params.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";

contract Monitor is KeeperCompatibleInterface {
    /*  @param protocol                The iLend contract address
        @param loanID                  The identifier of the loan to be liquidated
        @param depositAmount           Amount of collateral originally deposited (in ETH)
        @param debtAmount              Total USDC borrowed against this collateral
        @param collateralValue         Current USD value of the collateral held
        @param discountBasisPoints     Liquidator’s bonus, in basis points (e.g. 500 = 5%)
        @param currentValueToBorrow    Collateral value available to borrow (after L2B adjustment)
        @param shortfallUSD            USD shortfall below required collateralization
        @param liquidatableETH         Amount of ETH a liquidator can claim (including bonus)
        @param postDiscountEthRate     Effective ETH rate (USDC/ETH) after applying discount
        @param currentETHPrice          Latest ETH price (USDC per ETH) from the oracle
    */
    event LiquidationOpportunity(
        address indexed protocol,
        uint256 indexed loanID,
        uint256 depositAmount,
        uint256 debtAmount,
        uint256 collateralValue,
        uint256 discountBasisPoints,
        uint256 currentValueToBorrow,
        uint256 shortfallUSD,
        uint256 liquidatableETH,
        uint256 currentETHPrice,
        uint256 postDiscountETHPrice
    );
    using PriceConverter for AggregatorV3Interface;
    uint256 private constant PERCENTAGE_CHANGE_THRESHOLD = 5;
    uint256 private constant BASIS_POINT = 10000;
    uint256 private constant HUNDRED = 100;

    uint256 private lastETHPrice;
    AggregatorV3Interface private priceFeed;
    Collateral private collateral;
    address private iLendAddress;
    Params private params;

    constructor (address _paramsAddress, 
                address _priceFeedAddress, 
                address _collateral, 
                address _iLendAddress
                ) {
        priceFeed = AggregatorV3Interface (_priceFeedAddress);
        lastETHPrice = priceFeed.getPrice ();
        collateral = Collateral (_collateral);
        iLendAddress = _iLendAddress;
        params = Params (_paramsAddress);
    }
        

    function checkUpkeep (bytes calldata /*checkData*/) 
    external 
    view 
    override
    returns (bool upkeepNeeded, bytes memory /*performData*/) {
        upkeepNeeded = false;
        uint256 currentETHPrice = priceFeed.getPrice();
        int256 priceDiff = int256 (currentETHPrice - lastETHPrice);
        if (priceDiff < 0){
            uint256 absPriceDiff = uint256 (priceDiff * (-1));
            uint256 percentageChange = (absPriceDiff / lastETHPrice) * 1000;
            upkeepNeeded = percentageChange > PERCENTAGE_CHANGE_THRESHOLD;
        }
    }

    function performUpkeep (bytes calldata /**/) 
    external override
    {
        address [] memory addresses = collateral.get_collateral_depositor_addresses ();
        for (uint i=0; i< addresses.length; i++) {
            address dAddress = addresses [i];
            CollateralView [] memory depletedCollaterals = collateral.get_depeleted_collaterals (dAddress);
            for (uint256 j=0; j<depletedCollaterals.length;j++) {
                CollateralView memory cv = depletedCollaterals [j];
                uint256 lqTh = params.getLiquidationThreshold ();
                uint256 discountRate = params.getLiquidationDiscountRate ();
                uint256 currentRate = priceFeed.getPrice ();

                uint256 currentCollateralValue = currentRate * cv.depositAmount * HUNDRED;
                uint256 currentValueToBorrow = currentCollateralValue / cv.totalUSDCBorrowed; 

                uint256 requiredCollateralForMeetingThreshold = cv.totalUSDCBorrowed * lqTh;
                uint256 shortFallUSD = (currentCollateralValue/HUNDRED) - requiredCollateralForMeetingThreshold;
                shortFallUSD = shortFallUSD <0? 0 : shortFallUSD;
                
                uint256 liquidableETH = shortFallUSD / currentRate;
                uint256 postDiscountETHPrice = (currentRate * (HUNDRED - discountRate))/HUNDRED; 
                emit LiquidationOpportunity 
                    (iLendAddress,
                    cv.loanID,
                    cv.depositAmount,
                    cv.totalUSDCBorrowed,
                    cv.totalCollateralDepost,
                    discountRate,
                    currentValueToBorrow,
                    shortFallUSD,
                    liquidableETH,
                    currentRate,
                    postDiscountETHPrice
                    );
            }
        }
    }
}