//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {KeeperCompatibleInterface} from
    "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/KeeperCompatibleInterface.sol";
import {PriceConverterLib} from "../lib/PriceConverterLib.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {CollateralView, LiquidationReadyCollateral} from "../shared/SharedStructures.sol";
import {Params} from "../misc/Params.sol";
import {AggregatorV3Interface} from "@chainlink-interfaces/AggregatorV3Interface.sol";
import {LiquidationRegistry} from "../liquidation/LiquidationRegistry.sol";
import {iLend} from "../ILend.sol";
import {console} from "../../lib/forge-std/src/Script.sol";

/**
 * register Monitor as an upkeep at https://automation.chain.link/sepolia
 *
 *
 */
contract Monitor is KeeperCompatibleInterface {
    error OnlyOwnerCanAccessThisFunction(address sender, address owner);
    error InvalidAccessRequest();

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

    uint256 private constant PERCENTAGE_CHANGE_THRESHOLD = 1;
    uint256 private constant BASIS_POINT = 10000;
    uint256 private constant HUNDRED = 100;
    uint256 private constant DUMMY_INIT_PRICE = 2200e18;
    uint256 private constant DUMMY_CURRENT_PRICE_PERCENTAGE = 72;
    uint256 private constant ETH_WEI = 1e18;
    uint256 private constant USDC_WEI = 1e6;
    uint256 private constant TIME_THRESHOLD = 1 days;

    uint256 private sLastETHPrice;
    AggregatorV3Interface private immutable iPriceFeed;
    Collateral private immutable iCollateral;
    Params private immutable iParams;
    LiquidationRegistry private immutable iLiquidationRegistry;
    uint256 private sLastCheckTimestamp;


    address private facadeContractAddress;
    address private immutable iOwnerAddress;

    bool private sTesting;

    modifier only_owner_contract(address _sender) {
        if (_sender != iOwnerAddress) {
            revert OnlyOwnerCanAccessThisFunction(_sender, iOwnerAddress);
        }
        _;
    }

    /**
     * @notice Initializes the contract with addresses of dependent modules and records the initial ETH price.
     * @dev Sets up references to external contracts and captures the latest ETH price at deployment time
     * for future comparison in upkeep checks.
     * @param _paramsAddress The address of the Params contract containing protocol-level parameters.
     * @param _priceFeedAddress The address of the ETH price feed contract.
     * @param _collateral The address of the Collateral contract used to fetch depositor collateral info.
     * @param _liquidationQuryAddress The address of the LiquidationRegistry contract to store liquidatable collaterals.
     */
    constructor(
        address _paramsAddress,
        address _priceFeedAddress,
        address _collateral,
        address _liquidationQuryAddress
    ) {
        iPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        sLastETHPrice = iPriceFeed.get_price();
        iCollateral = Collateral(_collateral);
        iParams = Params(_paramsAddress);
        iLiquidationRegistry = LiquidationRegistry(_liquidationQuryAddress);
        iOwnerAddress = msg.sender;
        sLastCheckTimestamp = block.timestamp;
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
    function checkUpkeep(bytes calldata /*checkData*/ )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /*performData*/ )
    {
        
        upkeepNeeded = false;
        if (has_time_threshold_reached ()) {
            uint256 currentETHPrice = iPriceFeed.get_price();

            int256 priceDiff = int256(currentETHPrice) - int256(sLastETHPrice);
            uint256 absPriceDiff = priceDiff >= 0 ? 0 : uint256(-priceDiff);

            uint256 percentageChange = (absPriceDiff * 100) / sLastETHPrice;
            upkeepNeeded = percentageChange > PERCENTAGE_CHANGE_THRESHOLD;
        }
    }

/**@notice Computes key liquidation metrics for a collateralized position.
     @dev
    - `cvu` is the USD value of the deposited ETH collateral (`rateWei/1e18 * depositAmount/1e18`).  
    - `v2b` is the collateral-to-debt ratio as a percentage:  
        • `>100` ⇒ over-collateralized  
        • `<100` ⇒ under-collateralized  
    - `req` is the USD collateral required to satisfy the threshold (`borrowedUSDC`).  
    - `sf` is the USD shortfall (zero if no shortfall).  
    - `le` is the amount of ETH (in wei) liquidatable to cover `sf`.  
    - `dp` is the ETH price after applying a discount of `discBP` basis points.
    @param v        A `CollateralView` containing `depositAmount` (wei) and `totalUSDCBorrowed` (USDC-wei).
    @param rateWei  Current ETH price in USDC-wei per ETH (USDC × 1e6 per 1e18 wei).
    @param discBP   Liquidation discount rate, in basis points (e.g. 500 = 5%).
    @return v2b     Collateral-to-borrow ratio as a percent (cvu × 100 / borrowedUSDC).
    @return sf      USD shortfall (max(req – cvu, 0)).
    @return le      ETH (wei) liquidatable to cover `sf` (sf / ( rateWei / 1e18 ) ).
    @return dp      Discounted ETH price ( rateWei/1e18 × (100 – discBP) / 100 ).
 **/
function calculate_liquidation_parameters(
        CollateralView memory v,
        uint256 rateWei,   // ETH price in USDC with 18 decimals (e.g., 1450 * 1e18)
        uint256 discBP    // Discount in basis points (e.g., 500 for 5%)
    )
    internal
    pure
    returns (
        uint256 v2b,   // Value-to-borrow ratio (percentage)
        uint256 sf,    // Shortfall in USDC
        uint256 le,    // Liquidatable ETH (in wei)
        uint256 dp     // Post-discount ETH price in USDC
    )
    {
        uint256 r  = rateWei / ETH_WEI;                // ETH price in USDC (e.g., 1450)
        uint256 da = v.depositAmount / ETH_WEI;        // Collateral in ETH (e.g., 5)
        uint256 ub = v.totalUSDCBorrowed / USDC_WEI;   // Borrowed USDC (e.g., 7500)

        uint256 cvu = r * da;                                  // Collateral value in USDC
                                                    // e.g., 1450 * 5 = 7250

        v2b = (cvu * HUNDRED) / ub;                    // Value-to-borrow ratio (%)
                                                    // e.g., (7250 * 100) / 7500 = 96.66

        uint256 req = ub;                                      // Required = borrowed (since LTV is 75%)
                                                    // e.g., 7500

        int256 diff = int256(req) - int256(cvu);       // Shortfall
                                                    // e.g., 7500 - 7250 = 250

        sf = diff > 0 ? uint256(diff) : 0;             // Only positive shortfall
                                                   // e.g., 250 

      
        le =  (sf  * ETH_WEI / r) ;                       // Liquidatable ETH (in wei)
        sf = sf * USDC_WEI;
        req = req * USDC_WEI;
        cvu = cvu * USDC_WEI;                                            // e.g., 
                                                    // (250 * 1e18) / 1450 
                                                    // = 172413793103448275862 WEI
                                                    // ≈ 0.17241 ETH

        dp = ((r * (HUNDRED - discBP)) * USDC_WEI) / HUNDRED;                   // Discounted ETH price
                                                    // e.g., (1450 * 95) * 1e6 ≈ 1377 USDC  ≈ 1377e6 WEI 
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
    function performUpkeep(bytes calldata /**/ ) external override {
        sLastCheckTimestamp = block.timestamp;
        sLastETHPrice = iPriceFeed.get_price();
        address[] memory addresses = iCollateral.get_collateral_depositor_addresses();
        iLiquidationRegistry.reset_liquidation_ready_collaterals();
        uint256 currentRate = sTesting == true ? get_dummy_current_price () :iPriceFeed.get_price();            
        uint256 discountRate = iParams.getLiquidationDiscountRate();
        for (uint256 i = 0; i < addresses.length; i++) {
            address dAddress = addresses[i];
            CollateralView[] memory depletedCollaterals = iCollateral.get_depeleted_collaterals(dAddress, currentRate);
            console.log (depletedCollaterals[0].depositAmount);
            for (uint256 j = 0; j < depletedCollaterals.length; j++) {
                CollateralView memory cv = depletedCollaterals[j];

                ( 
                    uint256 currentValueToBorrow,
                    uint256 shortFallUSD,
                    uint256 liquidableETH,
                    uint256 postDiscountETHPrice
                )
                = calculate_liquidation_parameters (cv, currentRate, discountRate);


                
                LiquidationReadyCollateral memory col = LiquidationReadyCollateral({
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

                emit LiquidationOpportunity(
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

    function register_caller_contracts(address _iLendAddress) external only_owner_contract(msg.sender) {
        facadeContractAddress = _iLendAddress;
        sTesting = (iLend (facadeContractAddress)).is_testing ();
    }

    function set_dummy_init_price_eth() public {
        if (msg.sender != iOwnerAddress && sTesting == true) {
            revert InvalidAccessRequest();
        }
        sLastETHPrice = DUMMY_INIT_PRICE;
    }

    function get_dummy_current_price () internal view returns (uint256){
        assert (sTesting == true);
        return (iPriceFeed.get_price() * DUMMY_CURRENT_PRICE_PERCENTAGE) / HUNDRED;
    }

    function has_time_threshold_reached () public view returns (bool) {
        if (sTesting == true)
            return true;
        else 
            return block.timestamp - sLastCheckTimestamp >= TIME_THRESHOLD;
    }
}
