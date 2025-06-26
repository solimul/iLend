// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;
import {LiquidationReadyCollateral} from "../shared/SharedStructures.sol";
import {LiquidationRegistry} from "../liquidation/LiquidationRegistry.sol";

contract LiquidationEngine {
    LiquidationRegistry private liqReg;
    uint256 private constant HUNDRED = 100;
    constructor (address _liquidationRegistryAddress) {
        liqReg = LiquidationRegistry (_liquidationRegistryAddress);
    }

    function quote_liquidation 
    (
        address _borrower, 
        uint256 _loanID
    ) 
    external view returns 
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
}