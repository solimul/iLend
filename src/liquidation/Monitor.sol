//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {KeeperCompatibleInterface} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {PriceConverterLib} from "../lib/PriceConverterLib.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {CollateralView, LiquidationReadyCollateral} from "../shared/SharedStructures.sol";
import {Params} from "../misc/Params.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {LiquidationRegistry} from "../liquidation/LiquidationRegistry.sol";
import {iLend} from "../ILend.sol";


contract Monitor is KeeperCompatibleInterface {
    /*  @param protocol                The iLend contract address
        @param borrowerAddress         The ID of the borrower
        @param loanID                  The identifier of the loan to be liquidated
        @param depositAmount           Amount of iCollateral originally deposited (in ETH)
        @param debtAmount              Total USDC borrowed against this iCollateral
        @param collateralValue         Current USD value of the iCollateral held
        @param discountBasisPoints     Liquidator’s bonus, in basis points (e.g. 500 = 5%)
        @param currentValueToBorrow    Collateral value available to borrow (after L2B adjustment)
        @param shortfallUSD            USD shortfall below required collateralization
        @param liquidatableETH         Amount of ETH a liquidator can claim (including bonus)
        @param postDiscountEthRate     Effective ETH rate (USDC/ETH) after applying discount
        @param currentETHPrice          Latest ETH price (USDC per ETH) from the oracle
        @param eventDateTime            Time when the event was created.
    */
    event LiquidationOpportunity(
        address indexed protocol,
        address indexed borrower,
        uint256 indexed loanID,
        uint256 depositAmount,
        uint256 debtAmount,
        uint256 collateralValue,
        uint256 discountBasisPoints,
        uint256 currentValueToBorrow,
        uint256 shortfallUSD,
        uint256 liquidatableETH,
        uint256 currentETHPrice,
        uint256 postDiscountETHPrice,
        uint256 eventDateTime
    );
    using PriceConverterLib for AggregatorV3Interface;
    uint256 private constant PERCENTAGE_CHANGE_THRESHOLD = 5;
    uint256 private constant BASIS_POINT = 10000;
    uint256 private constant HUNDRED = 100;

    uint256 private sLastETHPrice;
    AggregatorV3Interface private immutable iPriceFeed;
    Collateral private immutable iCollateral;
    address private immutable iLendAddress;
    Params private immutable iParams;
    LiquidationRegistry private immutable iLiquidationRegistry;

    iLend private facadeContract;

    
    /**
     * @notice Initializes the contract with addresses of dependent modules and records the initial ETH price.
     * @dev Sets up references to external contracts and captures the latest ETH price at deployment time 
     * for future comparison in upkeep checks.
     * @param _paramsAddress The address of the Params contract containing protocol-level parameters.
     * @param _priceFeedAddress The address of the ETH price feed contract.
     * @param _collateral The address of the Collateral contract used to fetch depositor collateral info.
     * @param _iLendAddress The address of the main lending contract (used in events).
     * @param _liquidationQuryAddress The address of the LiquidationRegistry contract to store liquidatable collaterals.
     */


    constructor (address _paramsAddress, 
            address _priceFeedAddress, 
            address _collateral, 
            address _iLendAddress,
            address _liquidationQuryAddress) {
        iPriceFeed = AggregatorV3Interface (_priceFeedAddress);
        sLastETHPrice = iPriceFeed.get_price ();
        iCollateral = Collateral (_collateral);
        iLendAddress = _iLendAddress;
        iParams = Params (_paramsAddress);
        iLiquidationRegistry = LiquidationRegistry (_liquidationQuryAddress);
    }

    /**
     * @notice Checks whether `performUpkeep` should be triggered based on ETH price movement.
     * @dev This function is called by Chainlink Automation nodes to determine if upkeep is needed.
     * It compares the current ETH price from the price feed with the last recorded price 
     * (`sLastETHPrice`) and calculates the percentage change. If the price has dropped more than 
     * a predefined threshold (`PERCENTAGE_CHANGE_THRESHOLD`), upkeep is marked as needed.
     *
     * Price increase does not trigger upkeep.
     *
     * @return upkeepNeeded A boolean indicating whether `performUpkeep` should be executed.
     * @return performData Placeholder for additional data (not used).
     */
   

    function checkUpkeep (bytes calldata /*checkData*/) 
    external 
    view 
    override
    returns (bool upkeepNeeded, bytes memory /*performData*/) {
        upkeepNeeded = false;
        uint256 currentETHPrice = iPriceFeed.get_price();
        int256 priceDiff = int256 (currentETHPrice - sLastETHPrice);
        if (priceDiff < 0){
            uint256 absPriceDiff = uint256 (priceDiff * (-1));
            uint256 percentageChange = (absPriceDiff / sLastETHPrice) * 1000;
            upkeepNeeded = percentageChange > PERCENTAGE_CHANGE_THRESHOLD;
        } else if (priceDiff > 0){
            upkeepNeeded = false;
        }
    }

    /**
     * @notice Identifies undercollateralized loans and marks them as eligible for liquidation.
     * @dev This function is intended to be called by Chainlink Automation (Keepers).
     * It loops through all collateral depositors and evaluates their depleted collaterals.
     * If a collateral's value falls below the liquidation threshold, it calculates the liquidation
     * parameters (such as shortfall, discounted ETH value) and registers the collateral in the 
     * `iLiquidationRegistry` for liquidation.
     *
     * Emits a `LiquidationOpportunity` event for each undercollateralized loan detected.
     *
     * Key calculations include:
     * - `currentValueToBorrow`: ratio of current collateral value to USDC borrowed.
     * - `shortFallUSD`: deficit amount below the required threshold (0 if not undercollateralized).
     * - `liquidableETH`: amount of ETH eligible for liquidation based on shortfall and ETH price.
     * - `postDiscountETHPrice`: ETH price after applying liquidation discount.
     */

    function performUpkeep (bytes calldata /**/) 
    external override
    {
        address [] memory addresses = iCollateral.get_collateral_depositor_addresses ();
        iLiquidationRegistry.reset_liquidation_ready_collaterals ();
        for (uint i=0; i< addresses.length; i++) {
            address dAddress = addresses [i];
            CollateralView [] memory depletedCollaterals = iCollateral.get_depeleted_collaterals (dAddress);
            for (uint256 j=0; j<depletedCollaterals.length;j++) {
                CollateralView memory cv = depletedCollaterals [j];
                uint256 lqTh = iParams.getLiquidationThreshold ();
                uint256 discountRate = iParams.getLiquidationDiscountRate ();
                uint256 currentRate = iPriceFeed.get_price ();

                uint256 currentCollateralValue = currentRate * cv.depositAmount * HUNDRED;
                uint256 currentValueToBorrow = currentCollateralValue / cv.totalUSDCBorrowed; 

                uint256 requiredCollateralForMeetingThreshold = cv.totalUSDCBorrowed * lqTh;
                uint256 shortFallUSD = (currentCollateralValue/HUNDRED) - requiredCollateralForMeetingThreshold;
                shortFallUSD = shortFallUSD <0? 0 : shortFallUSD;
                
                uint256 liquidableETH = shortFallUSD / currentRate;
                uint256 postDiscountETHPrice = (currentRate * (HUNDRED - discountRate))/HUNDRED; 
                LiquidationReadyCollateral memory col = LiquidationReadyCollateral ({
                    discountRate: discountRate,
                    currentValueToBorrow: currentValueToBorrow,
                    shortFallUSDC: shortFallUSD,
                    liquidableETH: liquidableETH,
                    currentRate: currentRate,
                    postDiscountETHPrice: postDiscountETHPrice,
                    cv: cv,
                    yetToBeLiquidated: true
                });

                iLiquidationRegistry.add_collateral_as_liquidation_ready(dAddress, col);

                emit LiquidationOpportunity 
                    (
                        iLendAddress,
                        dAddress,
                        cv.loanID,
                        cv.depositAmount,
                        cv.totalUSDCBorrowed,
                        cv.totalCollateralDepost,
                        discountRate,
                        currentValueToBorrow,
                        shortFallUSD,
                        liquidableETH,
                        currentRate,
                        postDiscountETHPrice,
                        block.timestamp
                    );
            }
        }
    }

    function register_caller_contracts (iLend _iLend) external {
        facadeContract = _iLend;
    }
}