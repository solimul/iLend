// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;
import {LiquidationReadyCollateral} from "../shared/SharedStructures.sol";
import {LiquidationRegistry} from "../liquidation/LiquidationRegistry.sol";
import {Collateral} from "../collateral/Collateral.sol";
import {Deposit} from "../deposit/Deposit.sol";
import {Liquidator, LiquidationRecord, LiquidationReadyCollateralLoanIDMap} from "../shared/SharedStructures.sol";

import {iLend} from "../ILend.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract LiquidationEngine {

    event LiquidationCompleted(
        address indexed liquidator,
        address indexed borrower,
        uint256 loanID,
        uint256 usdcAmount,
        uint256 ethReceived,
        uint256 timeStamp
    );

    event LiquidationReceived(
        address indexed liquidator,
        uint256 usdcAmount,
        uint256 poolBalance,
        uint256 timestamp
    );

    error BorrowerDoesNotHaveEnoughUSDCForLiquidation(
        address borrower,
        uint256 loanID,
        address liquidator,
        uint256 usdcSent,
        uint256 shortfallRequired
    );

    error LiquidatorDoesNotHaveEnoughUSDC(
        address liquidator,
        uint256 usdcSent,
        uint256 usdcBalance
    );

    error NotEnoughLiquidableETHForDiscountedLiquidation(
        address borrower,
        uint256 loanID,
        uint256 availableETH,
        uint256 requiredETH
    );

    error NotEnoughLiquidableETH(
        address borrower,
        uint256 loanID,
        uint256 availableLiquidableETH,
        uint256 requiredETH
    );

    error OnlyILendContractCanAccessThisFunction (address sender, address ilend);
    error OnlyOwnerCanAccessThisFunction (address sender, address owner);

    LiquidationRegistry private immutable iLiqReg;
    Collateral private immutable  iCollateral;
    Deposit private immutable iDeposit;
    uint256 private constant HUNDRED = 100;

    address [] iLiquidatorsList;
    mapping (address => Liquidator) iLiquidatorsMap;
    address private facadeContractAddress;
    IERC20 private usdcToken;
    address private immutable iOwnerAddress;

    modifier only_facade_contract(address _sender) {
        if (_sender != facadeContractAddress) {
            revert OnlyILendContractCanAccessThisFunction (_sender, facadeContractAddress);
        }
        _;
    }

    modifier only_owner_contract (address _sender) {
        if (_sender != iOwnerAddress) {
            revert OnlyOwnerCanAccessThisFunction (_sender, iOwnerAddress);
        }
        _;
    }

    /**
     * @notice Initializes the LiquidationEngine contract with required component contract addresses.
     * @dev Sets up references to external contracts for liquidation registry, collateral management,
     * deposit pool, and transaction handling.
     *
     * @param _liquidationRegistryAddress The address of the LiquidationRegistry contract.
     * @param _collateralAddress The address of the Collateral contract.
     * @param _depositAddress The address of the Deposit contract.
     */

    constructor (address _liquidationRegistryAddress,
        address _collateralAddress,
        address _depositAddress,
        address _usdcAddress) {
        iLiqReg = LiquidationRegistry (_liquidationRegistryAddress);
        iCollateral = Collateral (_collateralAddress);
        iDeposit = Deposit (_depositAddress);
        usdcToken = IERC20 (_usdcAddress);
        iOwnerAddress = msg.sender;
    }

    /**
     * @notice Provides a quote for liquidating a specific borrower's loan.
     * @dev 
     * - Fetches the `LiquidationReadyCollateral` for the given borrower and loan ID.
     * - Calculates the USDC shortfall and the corresponding amount of ETH the liquidator would receive,
     *   including a liquidation bonus defined by `discountRate`.
     * - Verifies that the available liquidable ETH is sufficient to cover the calculated amount.
     *
     * @param _borrower The address of the borrower whose position is being considered for liquidation.
     * @param _loanID The ID of the loan to quote liquidation for.
     * @return shortFallUSDC The total USDC shortfall required to restore collateralization.
     * @return ethToReceive The amount of ETH a liquidator would receive in return, including the discount bonus.
     */


    function quote_liquidation 
    (
        address _borrower, 
        uint256 _loanID
    ) 
    public 
    view 
    returns (uint256 shortFallUSDC, uint256 ethToReceive) {
        LiquidationReadyCollateral memory col = iLiqReg.get_liquidation_collateral(_borrower, _loanID);
        shortFallUSDC = col.shortFallUSDC;
        uint256 bonus = HUNDRED + col.discountRate;
        uint256 usdcWithBonus = col.shortFallUSDC * bonus;
        ethToReceive  = usdcWithBonus / (col.currentRate*HUNDRED); 
        if (col.liquidableETH < ethToReceive)
            revert NotEnoughLiquidableETH(
                _borrower, 
                _loanID, 
                col.liquidableETH, 
                ethToReceive
            );
    }

    /**
     * @notice Updates internal records after a successful liquidation.
     * @dev 
     * - If the liquidator is new, adds them to the `iLiquidatorsList` and initializes their entry in `iLiquidatorsMap`.
     * - Increments the liquidator’s total USDC provided and total discounted ETH received.
     * - Creates a new `LiquidationRecord` with full details of the liquidation, including the fetched collateral and timestamp.
     * - Appends the record to the liquidator’s history.
     * - Emits a `LiquidationCompleted` event with full liquidation details.
     *
     * @param _liquidator The address of the liquidator who performed the liquidation.
     * @param _borrower The address of the borrower whose position was liquidated.
     * @param _loanID The ID of the loan that was liquidated.
     * @param _usdcAmount The amount of USDC paid by the liquidator.
     * @param _ethRecieved The amount of discounted ETH received by the liquidator.
     */

    function update_liquidation_records 
    ( 
        address _liquidator,
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount,
        uint256 _ethRecieved
    ) 
    internal {
        Liquidator storage liquidatorInfo = iLiquidatorsMap [_liquidator];

        if (liquidatorInfo.liquidator  == address (0)) { // new liquidator
            iLiquidatorsList.push (_liquidator);
            liquidatorInfo.liquidator = _liquidator;
        }
        liquidatorInfo.totalLiquidatProvided += _usdcAmount;
        liquidatorInfo.totalDiscountedAssetReceived += _ethRecieved;
        LiquidationRecord memory liqRecord = LiquidationRecord ({
            liquidationUSDCAmount: _usdcAmount,
            discountedETHRecieved: _ethRecieved,
            liquidatedCollateral: iLiqReg.get_liquidation_collateral(_borrower, _loanID),
            liquidInjectionDateTime: block.timestamp
        });
        liquidatorInfo.liquidationRecords.push (liqRecord);

        emit LiquidationCompleted (_liquidator, _borrower, _loanID, _usdcAmount, _ethRecieved, block.timestamp);
    }

    /**
     * @notice Processes a liquidation event by validating the liquidator’s USDC payment and determining ETH to be transferred.
     * @dev 
     * - Quotes the required USDC shortfall and corresponding ETH amount via `quote_liquidation`.
     * - Validates that the liquidator sent enough USDC to cover the shortfall.
     * - Checks that the liquidator has sufficient USDC balance and that the collateral has enough ETH to be liquidated.
     * - Delegates state updates to `update_liquidation_records`.
     * 
     *
     * @param _liquidator The address of the entity performing the liquidation.
     * @param _borrower The address of the borrower whose position is being liquidated.
     * @param _loanID The ID of the loan associated with the liquidation.
     * @param _usdcAmount The amount of USDC sent by the liquidator for covering the shortfall.
     * @return ethToTransfer The amount of ETH that will be transferred to the liquidator in exchange for the USDC.
     */


    function update_on_liquidation_deposit 
    (
        address _liquidator,
        address _borrower,
        uint256 _loanID,
        uint256 _usdcAmount
    ) 
    external 
    only_facade_contract (msg.sender)
    returns (uint256)
    {
        (uint256 shortFallUSDC, uint256 ethToTransfer) = quote_liquidation (_borrower, _loanID);
        if (_usdcAmount < shortFallUSDC)
            revert BorrowerDoesNotHaveEnoughUSDCForLiquidation(
                _borrower, 
                _loanID, 
                _liquidator, 
                _usdcAmount, 
                shortFallUSDC
            );
        uint256 lBalance = usdcToken.balanceOf (address (_liquidator));
        if (_usdcAmount < lBalance)
            revert LiquidatorDoesNotHaveEnoughUSDC(
                _liquidator, 
                _usdcAmount, 
                lBalance
            );
        uint256 collateralETH = iCollateral.get_collateral_ETH_by_record (_borrower, _loanID);
        if (ethToTransfer > collateralETH)
            revert NotEnoughLiquidableETHForDiscountedLiquidation(
                _borrower, 
                _loanID, 
                collateralETH,
                ethToTransfer
            );
        update_liquidation_records (_liquidator,_borrower,_loanID,_usdcAmount, ethToTransfer);
        return ethToTransfer;
    }

    /**
     * @notice Checks whether a given address is registered as a liquidator.
     * @dev Looks up the `iLiquidatorsMap` and verifies if the stored liquidator address is non-zero.
     * @param _liquidator The address to check for liquidator status.
     * @return A boolean indicating whether the address is a registered liquidator.
     */

    function is_a_liquidator 
    (
        address _liquidator
    ) 
    public 
    view 
    returns (bool) {
        return iLiquidatorsMap[_liquidator].liquidator != address(0);
    }

    /**
     * @notice Checks whether a specific collateral is still pending liquidation.
     * @dev Retrieves the `LiquidationReadyCollateral` from the liquidation registry and 
     * returns the value of its `yetToBeLiquidated` flag.
     * @param _borrower The address of the borrower whose collateral status is being queried.
     * @param _loanID The loan ID associated with the collateral.
     * @return A boolean indicating whether the collateral is yet to be liquidated.
     */

    function yet_to_be_liquidated 
    (
        address _borrower,
        uint256 _loanID
    )
    public
    view
    returns (bool) {
        LiquidationReadyCollateral memory col = iLiqReg.get_liquidation_collateral(_borrower, _loanID);
        return col.yetToBeLiquidated;
    }

    function register_caller_contracts 
    (
        address _iLendContractAddress
    ) 
    external
    only_owner_contract (msg.sender) {
        facadeContractAddress = _iLendContractAddress;
    }
}