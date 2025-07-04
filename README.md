# 🛡️ iLend Protocol

**iLend** is a decentralized lending protocol that enables users to deposit assets as collateral and borrow against them. This repository is provisioned with a **Liquidation Engine**, a subsystem responsible for monitoring undercollateralized loans and enabling liquidators to stabilize the system.

---

## 📦 Modules Overview

### 🧱 Core Contracts

- **`Collateral.sol`**  
  Handles collateral deposits, tracks depositors, and provides data on each deposit including associated borrowings.

- **`LiquidationQuery.sol`**  
  Maintains an **on-chain registry** of liquidation-ready collaterals. Allows querying by borrower and loan ID.

- **`Monitor.sol`**  
  Uses **Chainlink Automation** to monitor asset price drops. Emits `LiquidationOpportunity` events and updates on-chain state in `LiquidationQuery`.

- **`LiquidationEngine.sol`**  
  Offers real-time liquidation quotes. Accepts loanID + borrower and returns:
  - `shortfallUSDC`: how much a liquidator needs to pay.
  - `ethToReceive`: how much discounted ETH they get.

- **`PricefeedManager.sol` & `PriceConverter.sol`**  
  Wrappers over Chainlink price feeds. Provide clean conversion logic between ETH and USDC.

- **`Params.sol`**  
  Stores protocol-wide configuration like:
  - Liquidation threshold (bps)
  - Liquidator discount (bps)

- **`SharedStructures.sol`**  
  Defines the key data structures:
  - `CollateralView`
  - `LiquidationReadyCollateral`

---

## 🔁 System Flow

1. **Collateralization**  
   Users deposit ETH and borrow USDC using `iLend`.

2. **Monitoring**  
   - `Monitor` uses Chainlink Automation to periodically check price drops.
   - If collateral is under threshold, it emits `LiquidationOpportunity` and updates `LiquidationQuery`.

3. **Liquidation Readiness**  
   - Bots and dApps can **off-chain query** `LiquidationQuery` or **listen to events**.
   - Collateral status is available via:
     - `get_list_of_liqudation_ready_addresses()`
     - `get_liquidation_ready_collateral_information_for_the_borrower()`

4. **Quote Generation**  
   - Liquidators use `quote_liquidation(borrower, loanID)` from `LiquidationEngine` to get:
     - `shortfallUSDC`
     - `ethToReceive`

5. **Liquidation Execution**  
   - Liquidators transfer `shortfallUSDC` to the protocol.
   - Protocol sends discounted ETH (based on predefined discount rate).

---

## 📊 Data Flows & Indexing

- **On-chain Registry**  
  - `LiquidationQuery` maintains borrower ↔ loan ↔ collateral mapping.

- **Off-chain Indexing**  
  - Events like `LiquidationOpportunity` can be indexed by The Graph or custom bots.
  - Naming follows standard conventions for better compatibility.

---

## 🔧 Deployment

1. Deploy shared libraries (`Params`, `PricefeedManager`, etc.)
2. Deploy core modules in order:
   - `Collateral.sol`
   - `LiquidationQuery.sol`
   - `Monitor.sol` (pass addresses of Collateral, Params, PriceFeed, iLend)
3. Set Chainlink automation job with `checkUpkeep()` logic.


## 🧠 Naming Conventions

- Standard event names like `LoanUnderCollateralized`, `LiquidationOpportunity`
- Indexable `loanID`, `borrower`, `protocol` fields

---

## 📬 Off-Chain Access

- `view`/`pure` functions can be called using Web3 `eth_call`
- No gas cost for these read-only operations
- Compatible with dApps and bots monitoring the system

---

## 🤝 Contributing

1. Fork and clone
2. Make changes to one of the modules
3. Run linter and test cases
4. Submit a pull request with a clear description

---

## 📄 License

MIT License
