// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";
// Borrow module
import "../src/borrow/Borrow.sol";

// Collateral module
import "../src/collateral/Collateral.sol";
import "../src/collateral/CollateralPool.sol";

// Deposit module
import "../src/deposit/Deposit.sol";
import "../src/deposit/DepositPool.sol";

// Liquidation module
import "../src/liquidation/LiquidationEngine.sol";
import "../src/liquidation/LiquidationRegistry.sol";
import "../src/liquidation/Monitor.sol";

// Misc module
import "../src/misc/Params.sol";
import "../src/misc/ProtocolReward.sol";
import "../src/misc/Transcation.sol";  // Note: possible typo in filename — should it be "Transaction.sol"?

// Repayment module
import "../src/repayment/Payback.sol";

// Treasury module
import "../src/treasury/Treasury.sol";

// Shared interface
import "../src/ILend.sol";


contract UnitTest is Test {
    Borrow private immutable iBorrow;
    Collateral private immutable iCollateral;
    CollateralPool private immutable iCollateralPool;
    Deposit private immutable iDeposit;
    DepositPool private immutable iDepositPool;
    LiquidationEngine private immutable iLiquidationEngine;
    LiquidationRegistry private immutable iLiquidationRegistry;
    Monitor private immutable iMonitor;
    Params private immutable iParams;
    ProtocolReward private immutable iProtocolReward;
    Transaction private immutable iTransaction;
    Payback private immutable iPayback;
    Treasury private immutable iTreasury;
    ILend private immutable iLend;



    function setUp() public virtual {
        
    }

    // Add helper functions here
}
