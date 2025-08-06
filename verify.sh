ETHERSCAN_API_KEY="$1"
CHAIN_ID="$2"
DEPLOYMENT_SCRIPT="$3"
PRIVATE_KEY="$4"
USDC="$5"
ETH="$6"
PRICE_FEED="$7"
shift 7
MAPPING=("$@")

BROADCAST_FILE="broadcast/$DEPLOYMENT_SCRIPT/$CHAIN_ID/run-latest.json"

if [[ ! -f "$BROADCAST_FILE" ]]; then
  echo "Broadcast file not found: $BROADCAST_FILE"
  exit 1
fi

# Dynamically parse deployed libraries
declare -A DEPLOYED_LIBS
while IFS="=" read -r name address; do
  DEPLOYED_LIBS["$name"]="$address"
done < <(jq -r '.transactions[] | select(.contractName | endswith("Lib")) | "\(.contractName)=\(.contractAddress)"' "$BROADCAST_FILE")

# Parse CONTRACT_TO_LIBS map
declare -A CONTRACT_TO_LIBS
for entry in "${MAPPING[@]}"; do
  contract="${entry%%:*}"
  libs="${entry#*:}"
  CONTRACT_TO_LIBS["$contract"]="$libs"
done

get_address() {
  local contract_name="$1"
  jq -r --arg name "$contract_name" '.transactions | reverse | map(select(.contractName == $name)) | .[0].contractAddress' "$BROADCAST_FILE"
}


build_libraries_flag() {
  local contract="$1"
  local lib_string="${CONTRACT_TO_LIBS[$contract]}"
  local libs_flag=""
  IFS=',' read -ra libs <<< "$lib_string"
  for lib in "${libs[@]}"; do
    if [[ -n "$lib" && -n "${DEPLOYED_LIBS[$lib]:-}" ]]; then
      libs_flag+="${libs_flag:+,}src/lib/${lib}.sol:${lib}:${DEPLOYED_LIBS[$lib]}"
    fi
  done
  [[ -n "$libs_flag" ]] && echo "--libraries $libs_flag"
}

encode_constructor_args() {
  local contract="$1"
  case "$contract" in
    Collateral)
      cast abi-encode "constructor(address,address,address)"             "$(get_address Params)" "$PRICE_FEED" "$ETH"
      ;;
    Borrow|Deposit|Payback|Monitor|LiquidationEngine|LiquidationRegistry)
      cast abi-encode "constructor(address)" "$(get_address Params)"
      ;;
    iLend)
      cast abi-encode "constructor(address,address,address,address,address,address,address,address)"             "$(get_address Params)"             "$(get_address Deposit)"             "$(get_address Collateral)"             "$(get_address Borrow)"             "$(get_address Treasury)"             "$(get_address Payback)"             "$(get_address LiquidationEngine)"             "$(get_address Monitor)"
      ;;
    *)
      echo ""  # No constructor args
      ;;
  esac
}

declare -A CONTRACT_TO_PATH=(
  [Collateral]="src/collateral/Collateral.sol"
  [Borrow]="src/borrow/Borrow.sol"
  [Deposit]="src/deposit/Deposit.sol"
  [Payback]="src/repayment/Payback.sol"
  [Monitor]="src/liquidation/Monitor.sol"
  [LiquidationEngine]="src/liquidation/LiquidationEngine.sol"
  [LiquidationRegistry]="src/liquidation/LiquidationRegistry.sol"
  [Params]="src/misc/Params.sol"
  [Treasury]="src/treasury/Treasury.sol"
  [iLend]="src/ILend.sol"
)

for contract in "${!CONTRACT_TO_LIBS[@]}"; do
  echo "Verifying $contract..."
  address=$(get_address "$contract")

  [[ -z "$address" || "$address" == "null" ]] && echo "Address not found for $contract" && continue

  args=$(encode_constructor_args "$contract")
  lib_flag=$(build_libraries_flag "$contract")
  cmd=(forge verify-contract "$address" "${CONTRACT_TO_PATH[$contract]}:$contract"
       --etherscan-api-key "$ETHERSCAN_API_KEY"
       --chain-id "$CHAIN_ID"
       --verifier etherscan
       --watch)

  [[ -n "$args" ]] && cmd+=(--constructor-args "$args")
  [[ -n "$lib_flag" ]] && cmd+=(--libraries "$lib_flag")

  echo "Running: ${cmd[*]}"
  "${cmd[@]}"
  sleep 2 
done