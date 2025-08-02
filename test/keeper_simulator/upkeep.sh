while true
do
    cast send <Monitor_Address> "checkUpkeep(bytes)" 0x --rpc-url http://localhost:8545
    cast send <Monitor_Address> "performUpkeep(bytes)" 0x --private-key <PK> --rpc-url http://localhost:8545
    sleep 10
done