#!/bin/bash

extract_contracts() {
  local SCRIPT_NAME="$1"
  local CHAIN_ID="$2"
  local BROADCAST_FILE="broadcast/${SCRIPT_NAME}/${CHAIN_ID}/run-latest.json"

  if [ -z "$SCRIPT_NAME" ] || [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <SCRIPT_NAME> <CHAIN_ID>" >&2
    echo "Example: $0 DeployILend.s.sol 11155111" >&2
    return 1
  fi

  if [ ! -f "$BROADCAST_FILE" ]; then
    echo "File not found: $BROADCAST_FILE" >&2
    return 1
  fi

  jq -r '.transactions[] | select(.contractAddress != null) | "\(.contractName) \(.contractAddress)"' "$BROADCAST_FILE" \
    | sort | uniq
}

# ===== Main =====
contracts_output=$(extract_contracts "$1" "$2")

if [ $? -eq 0 ]; then
  echo "$contracts_output"
fi
