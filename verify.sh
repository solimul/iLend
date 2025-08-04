#!/usr/bin/env bash
set -euo pipefail

ETHERSCAN_API_KEY="$1"
CHAIN_ID="$2"
DEPLOY_SCRIPT="$3"
PRIVATE_KEY="$4"
USDC_CONTRACT_ADDR="$5"
ETH_CONTRACT_ADDR="$6"         

if [[ -z "$ETHERSCAN_API_KEY" || -z "$CHAIN_ID" || -z "$DEPLOY_SCRIPT" || -z "$PRIVATE_KEY" ]]; then
  echo "Usage: $0 <ETHERSCAN_API_KEY> <CHAIN_ID> <DEPLOY_SCRIPT> <PRIVATE_KEY>"
  exit 1
fi

BROADCAST="broadcast/${DEPLOY_SCRIPT}/${CHAIN_ID}/run-latest.json"

get_address() {
  jq -r ".transactions[] | select(.contractName == \"$1\") | .contractAddress" "$BROADCAST" | tail -1
}

forge_verify() {
  local CONTRACT="$1"
  local CONTRACT_PATH="$2"
  local ARG_TYPES="$3"
  shift 3
  local ADDR_ARGS=("$@")

  local ADDRESS
  ADDRESS=$(get_address "$CONTRACT")
  if [[ -z "$ADDRESS" ]]; then
    echo "Could not find address for $CONTRACT"
    return
  fi

  echo "Verifying $CONTRACT at $ADDRESS..."

  if [[ -n "$ARG_TYPES" ]]; then
    local ENCODED_ARGS
    ENCODED_ARGS=$(cast abi-encode "constructor($ARG_TYPES)" "${ADDR_ARGS[@]}")
    forge verify-contract "$ADDRESS" "$CONTRACT_PATH:$CONTRACT" \
      --constructor-args "$ENCODED_ARGS" \
      --etherscan-api-key "$ETHERSCAN_API_KEY" \
      --chain-id "$CHAIN_ID" \
      --verifier etherscan \
      --num-of-optimizations 200 \
      --watch
  else
    forge verify-contract "$ADDRESS" "$CONTRACT_PATH:$CONTRACT" \
      --etherscan-api-key "$ETHERSCAN_API_KEY" \
      --chain-id "$CHAIN_ID" \
      --verifier etherscan \
      --num-of-optimizations 200 \
      --watch
  fi
}

DEPLOYER_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")

# ==== Contract Verifications ====

forge_verify Params src/misc/Params.sol "bool,bool,bool" \
  false false false

forge_verify Treasury src/treasury/Treasury.sol ""

forge_verify Collateral src/collateral/Collateral.sol "address,address,address" \
  "$(get_address Params)" \
  "$ETH_CONTRACT_ADDR" \
  "$(get_address Treasury)"

forge_verify Deposit src/deposit/Deposit.sol "address,address,address" \
  "$(get_address Params)" \
  "$USDC_CONTRACT_ADDR" \
  "$(get_address Collateral)"

forge_verify Borrow src/borrow/Borrow.sol "address,address,address,address,address" \
  "$(get_address Params)" \
  "$(get_address AggregatorV3Interface)" \
  "$(get_address Deposit)" \
  "$(get_address Collateral)" \
  "$(get_address USDC_CONTRACT_ADDR)"

forge_verify Payback src/repayment/Payback.sol "address,address,address,address" \
  "$(get_address Borrow)" \
  "$(get_address Deposit)" \
  "$(get_address Treasury)" \
  "$(get_address USDC_CONTRACT_ADDR)"

forge_verify LiquidationRegistry src/liquidation/LiquidationRegistry.sol ""

forge_verify Monitor src/liquidation/Monitor.sol "address,address,address,address,address" \
  "$(get_address Params)" \
  "$(get_address AggregatorV3Interface)" \
  "$(get_address Collateral)" \
  "$DEPLOYER_ADDRESS" \
  "$(get_address LiquidationRegistry)"

forge_verify LiquidationEngine src/liquidation/LiquidationEngine.sol "address,address,address,address" \
  "$(get_address LiquidationRegistry)" \
  "$(get_address Collateral)" \
  "$(get_address Deposit)" \
  "$(get_address USDC_CONTRACT_ADDR)"

forge_verify iLend src/ILend.sol "address,address,address,address,address,address,address,address,address,address,address,address,bool" \
  "$(get_address Params)" \
  "$(get_address AggregatorV3Interface)" \
  "$(get_address USDC_CONTRACT_ADDR)" \
  "$(get_address USDC_CONTRACT_ADDR)" \
  "$(get_address Treasury)" \
  "$(get_address Collateral)" \
  "$(get_address Deposit)" \
  "$(get_address Borrow)" \
  "$(get_address Payback)" \
  "$(get_address LiquidationRegistry)" \
  "$(get_address Monitor)" \
  "$(get_address LiquidationEngine)" \
  false
