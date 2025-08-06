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
    uint256 private constant DUMMY_CURRENT_PRICE_PERCENTAGE = 90;
    uint256 private constant ETH_WEI = 1e18;
    uint256 private constant USDC_WEI = 1e6;

    uint256 private sLastETHPrice;
    AggregatorV3Interface private immutable iPriceFeed;
    Collateral private immutable iCollateral;
    Params private immutable iParams;
    LiquidationRegistry private immutable iLiquidationRegistry;

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
        uint256 currentETHPrice = iPriceFeed.get_price();

        int256 priceDiff = int256(currentETHPrice) - int256(sLastETHPrice);
        uint256 absPriceDiff = priceDiff >= 0 ? 0 : uint256(-priceDiff);

        uint256 percentageChange = (absPriceDiff * 100) / sLastETHPrice;

        upkeepNeeded = percentageChange > PERCENTAGE_CHANGE_THRESHOLD;
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
        address[] memory addresses = iCollateral.get_collateral_depositor_addresses();
        iLiquidationRegistry.reset_liquidation_ready_collaterals();
        uint256 currentRate = sTesting == true ? get_dummy_current_price () :iPriceFeed.get_price();            
        uint256 lqTh = iParams.getLiquidationThreshold();
        uint256 discountRate = iParams.getLiquidationDiscountRate();
        for (uint256 i = 0; i < addresses.length; i++) {
            address dAddress = addresses[i];
            // console.log (sTesting);
            // console.log (currentRate, iPriceFeed.get_price());
            // console.log (lqTh);
            // console.log (discountRate);

            CollateralView[] memory depletedCollaterals = iCollateral.get_depeleted_collaterals(dAddress, currentRate);
            console.log (depletedCollaterals[0].depositAmount);
            for (uint256 j = 0; j < depletedCollaterals.length; j++) {
                CollateralView memory cv = depletedCollaterals[j];


                uint256 currentCollateralValue = (currentRate /ETH_WEI) * (cv.depositAmount / ETH_WEI);
                uint256 currentValueToBorrow = (currentCollateralValue * HUNDRED) / (cv.totalUSDCBorrowed / USDC_WEI);
                uint256 requiredCollateralForMeetingThreshold = ((cv.totalUSDCBorrowed / USDC_WEI) * lqTh) / HUNDRED;
                int256 shortFallUSDInt = int256 (requiredCollateralForMeetingThreshold) - int256 (currentCollateralValue);
                uint256 shortFallUSD = shortFallUSDInt < 0 ? 0 : uint256 (shortFallUSDInt);
        

                uint256 liquidableETH = shortFallUSD / currentRate;
                uint256 postDiscountETHPrice = (currentRate * (HUNDRED - discountRate)) / HUNDRED;
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
}
