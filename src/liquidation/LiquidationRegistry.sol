//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {LiquidationReadyCollateral, LiquidationReadyCollateralLoanIDMap} from "../shared/SharedStructures.sol";
import {iLend} from "../ILend.sol";

contract LiquidationRegistry {

    error BorrowerDoesNotHaveLiquidationReadyCollateral(address borrower);

    address[] private sLiquidationReadyList;
    mapping (address => uint256 []) private sLiquidationReadyBorrower2LoanIDs;
    mapping (address=>LiquidationReadyCollateral []) private sLiquidationReadyCollaterals;
    mapping (address=> LiquidationReadyCollateralLoanIDMap) private sAddressToLoanIDToCollateral;
    iLend private facadeContract;

    
    /**
     * @notice Modifier to ensure that the specified borrower has at least one liquidation-ready collateral.
     * @dev Reverts if the borrower has no entries in the `sLiquidationReadyCollaterals` mapping.
     * This prevents access to functions that assume the presence of such collaterals.
     * @param _borrower The address of the borrower being validated.
     */

    modifier _borrowerExists (address _borrower) {
        if (sLiquidationReadyCollaterals [_borrower].length < 1)
            revert BorrowerDoesNotHaveLiquidationReadyCollateral(_borrower);
        _;
    }
    
    /**
     * @notice Registers a collateral as liquidation-ready for a given borrower.
     * @dev Adds the provided `LiquidationReadyCollateral` to multiple tracking structures:
     * - Appends to the borrower's list of liquidation-ready collaterals.
     * - Adds the borrower to the global `sLiquidationReadyList`.
     * - Records the loan ID under `sLiquidationReadyBorrower2LoanIDs`.
     * - Maps the collateral to the corresponding loan ID in `sAddressToLoanIDToCollateral`.
     * This ensures the collateral is fully tracked for potential liquidation and accessible by loan ID or borrower.
     * @param _borrower The address of the borrower whose collateral is being flagged.
     * @param _collateral The `LiquidationReadyCollateral` object containing details of the undercollateralized position.
     */

    function add_collateral_as_liquidation_ready 
    (
        address _borrower,
        LiquidationReadyCollateral memory _collateral
    ) 
    public {
        sLiquidationReadyCollaterals [_borrower].push (_collateral);
        sLiquidationReadyList.push (_borrower);
        sLiquidationReadyBorrower2LoanIDs [_borrower].push (_collateral.cv.loanID);
        LiquidationReadyCollateralLoanIDMap storage loanMap = sAddressToLoanIDToCollateral[_borrower];
        loanMap.map[_collateral.cv.loanID] = _collateral;
    }

    /**
     * @notice Clears all liquidation-ready collateral data across all borrowers.
     * @dev Iterates over all addresses in `sLiquidationReadyList` and deletes:
     * - The list of liquidation-ready loan IDs per borrower
     * - The detailed collateral mappings for each loan ID
     * - The array of liquidation-ready collaterals per borrower
     * - The entire collateral map per borrower
     * Finally, resets the `sLiquidationReadyList` itself.
     * This function is typically called before re-evaluating the liquidation state in an upkeep cycle.
     */

    function reset_liquidation_ready_collaterals () 
    public {
        for (uint256 i=0; i< sLiquidationReadyList.length; i++) {
            address cAddress = sLiquidationReadyList [i];
            uint256[] storage loanIDs = sLiquidationReadyBorrower2LoanIDs[cAddress];
        
            for (uint256 j = 0; j < loanIDs.length; j++) {
                delete sAddressToLoanIDToCollateral[cAddress].map[loanIDs[j]];
            }

            delete sLiquidationReadyCollaterals[cAddress];
            delete sLiquidationReadyBorrower2LoanIDs[cAddress];
            delete sAddressToLoanIDToCollateral[cAddress];
        }
        delete sLiquidationReadyList;
    }

    /**
     * @notice Retrieves the list of borrower addresses with at least one liquidation-ready collateral.
     * @dev Returns all addresses currently tracked in the `sLiquidationReadyList`, 
     * which contains borrowers flagged for potential liquidation.
     * @return An array of borrower addresses with liquidation-ready loans.
     */

    function get_liqudation_ready_addresses () external view  returns (address [] memory){
        return sLiquidationReadyList;
    }

    /**
     * @notice Returns all liquidation-ready collateral entries associated with a specific borrower.
     * @dev Requires that the borrower exists. Retrieves an array of `LiquidationReadyCollateral` 
     * structs that have been flagged for potential liquidation.
     * @param _borrower The address of the borrower whose liquidation-ready collaterals are being queried.
     * @return An array of `LiquidationReadyCollateral` structs associated with the borrower.
     */

    function get_liquidation_ready_collaterals_by_borrower 
    (
        address _borrower
    ) 
    external view 
    _borrowerExists (_borrower)
    returns (LiquidationReadyCollateral [] memory) {
        return sLiquidationReadyCollaterals [_borrower];
    }

    /**
     * @notice Retrieves the liquidation-ready collateral details for a specific borrower's loan.
     * @dev Ensures the borrower exists before returning the corresponding 
     * `LiquidationReadyCollateral` struct stored in the mapping.
     * @param _borrower The address of the borrower whose collateral data is being requested.
     * @param _loanID The loan ID for which the liquidation-ready collateral is retrieved.
     * @return A `LiquidationReadyCollateral` struct containing detailed liquidation information for the loan.
     */

    function get_liquidation_collateral ( address _borrower,
        uint256 _loanID) 
    external view
    _borrowerExists (_borrower) returns (LiquidationReadyCollateral memory){
        LiquidationReadyCollateralLoanIDMap storage col = sAddressToLoanIDToCollateral [_borrower];
        return col.map [_loanID];
    }

    /**
     * @notice Returns the list of loan IDs marked as liquidation-ready for a given borrower.
     * @dev Requires that the borrower exists in the system. The returned list includes only 
     * those loans that have been flagged as eligible for liquidation.
     * @param _borrower The address of the borrower whose liquidation-ready loan IDs are being queried.
     * @return An array of loan IDs that are ready for liquidation.
     */
    function get_liquidation_ready_loanIDs 
    (address _borrower) 
    external view
    _borrowerExists (_borrower)
    returns (uint256 [] memory) {
        return sLiquidationReadyBorrower2LoanIDs [_borrower];
    }

    function register_caller_contracts (iLend _iLend) external {
        facadeContract = _iLend;
    }
}