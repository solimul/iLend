//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {LiquidationReadyCollateral} from "../shared/SharedStructures.sol";

contract LiquidationQuery {
    address[] private liquidationReadyList;
    mapping (address=>LiquidationReadyCollateral []) private liquidationReadyCollaterals;

    function add_collateral_as_liquidation_ready 
    (
        address _borrower,
        LiquidationReadyCollateral memory _collateral
    ) 
    public {
        liquidationReadyCollaterals [_borrower].push (_collateral);
        liquidationReadyList.push (_borrower);
    }

    function reset_liquidation_ready_collaterals () 
    public {
        for (uint256 i=0; i< liquidationReadyList.length; i++) {
            address cAddress = liquidationReadyList [i];
            delete liquidationReadyCollaterals [cAddress];
        }
        delete liquidationReadyList;
    }

    function get_list_of_liqudation_ready_addresses () external view  returns (address [] memory){
        return liquidationReadyList;
    }

    function get_liquidation_ready_collateral_information_for_the_borrower 
    (
        address _borrower
    ) 
    external view returns (LiquidationReadyCollateral [] memory) {
        require (liquidationReadyCollaterals [_borrower].length > 0, "The borrower does not have any liquidation ready collateral.");
        return liquidationReadyCollaterals [_borrower];
    }
}