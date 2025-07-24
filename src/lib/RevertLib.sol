library RevertLib {
    /// @notice Reverts execution, returning `payload` as the revert data
    /// @param payload ABI‐encoded selector+arguments
    function dynamic_revert(bytes memory payload) internal pure {
        assembly {
            // first 32 bytes (0x20) is the length of the 'payload'   
            let ptr := add(payload, 0x20) // skip the 32‐byte length
            let len := mload(payload)     // load the length
            revert(ptr, len)              // revert with payload
        }
    }
}