//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {LiquidationReadyCollateral, LiquidationReadyCollateralLoanIDMap} from "../shared/SharedStructures.sol";

contract LiquidationRegistry {
    address[] private liquidationReadyList;
    mapping (address => uint256 []) private liquidationReadyBorrower2LoanIDs;
    mapping (address=>LiquidationReadyCollateral []) private liquidationReadyCollaterals;
    mapping (address=> LiquidationReadyCollateralLoanIDMap) private addressToLoanIDToCollateral;

    modifier _borrowerExists (address _borrower) {
        require (liquidationReadyCollaterals [_borrower].length > 0, "The borrower does not have any liquidation ready collateral.");
        _;
    }
    
    function add_collateral_as_liquidation_ready 
    (
        address _borrower,
        LiquidationReadyCollateral memory _collateral
    ) 
    public {
        liquidationReadyCollaterals [_borrower].push (_collateral);
        liquidationReadyList.push (_borrower);
        liquidationReadyBorrower2LoanIDs [_borrower].push (_collateral.cv.loanID);
        LiquidationReadyCollateralLoanIDMap storage loanMap = addressToLoanIDToCollateral[_borrower];
        loanMap.map[_collateral.cv.loanID] = _collateral;
    }

    function reset_liquidation_ready_collaterals () 
    public {
        for (uint256 i=0; i< liquidationReadyList.length; i++) {
            address cAddress = liquidationReadyList [i];
            uint256[] storage loanIDs = liquidationReadyBorrower2LoanIDs[cAddress];
        
            for (uint256 j = 0; j < loanIDs.length; j++) {
                delete addressToLoanIDToCollateral[cAddress].map[loanIDs[j]];
            }

            delete liquidationReadyCollaterals[cAddress];
            delete liquidationReadyBorrower2LoanIDs[cAddress];
            delete addressToLoanIDToCollateral[cAddress];
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
    external view 
    _borrowerExists (_borrower)
    returns (LiquidationReadyCollateral [] memory) {
        return liquidationReadyCollaterals [_borrower];
    }

    function get_liquidation_ready_collateral_information_for_the_borrower_and_loanID 
    (
        address _borrower,
        uint256 _loanID
    ) 
    external view
    _borrowerExists (_borrower) returns (LiquidationReadyCollateral memory){
        LiquidationReadyCollateralLoanIDMap storage col = addressToLoanIDToCollateral [_borrower];
        return col.map [_loanID];
    }

    function get_liquidation_ready_and_loanID_by_borrower 
    (address _borrower) 
    external view
    _borrowerExists (_borrower)
    returns (uint256 [] memory) {
        return liquidationReadyBorrower2LoanIDs [_borrower];
    }
}