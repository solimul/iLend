RPC_URL="$1"
PRIVATE_KEY="$2"
ETHERSCAN_API_KEY="$3"
OUTPUT_FILE="deployed-libs.json"

# Reset output file
echo "{}" > "$OUTPUT_FILE"

deploy_and_record() {
  local LIB_PATH=$1
  local LIB_NAME=$2

  echo "Deploying $LIB_NAME..."

  forge create "$LIB_PATH:$LIB_NAME" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --broadcast  > tmp_output.txt
    

  ADDRESS=$(grep -oE 'Deployed to: 0x[a-fA-F0-9]{40}' tmp_output.txt | awk '{print $3}')
  echo "✓ $LIB_NAME deployed at: $ADDRESS"

  jq --arg name "$LIB_NAME" --arg addr "$ADDRESS" '. + {($name): $addr}' "$OUTPUT_FILE" > tmp.json && mv tmp.json "$OUTPUT_FILE"
}

deploy_and_record src/lib/PricefeedManagerLib.sol PricefeedManagerLib
deploy_and_record src/lib/PriceConverterLib.sol PriceConverterLib
deploy_and_record src/lib/RevertLib.sol RevertLib
deploy_and_record src/lib/NetworkConfigLib.sol NetworkConfigLib

echo "✅ All libraries deployed. Addresses saved to $OUTPUT_FILE"
