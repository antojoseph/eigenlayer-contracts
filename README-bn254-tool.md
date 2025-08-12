# BN254 Key Generation Tool

This tool extracts the BN254 key generation logic from the secure enclave script and allows you to generate deterministic BN254 keypairs for testing and development.

## Usage

```bash
go run extract_bn254_key.go <scalar_value>
```

### Examples

```bash
# Using decimal scalar
go run extract_bn254_key.go 69
go run extract_bn254_key.go 12345

# Using hexadecimal scalar  
go run extract_bn254_key.go 0x1a2b3c4d5e6f
go run extract_bn254_key.go 0x45
```

## Output Formats

The tool provides multiple output formats useful for different purposes:

1. **JSON Format**: Same as the original enclave script
2. **EigenLayer Format**: Decimal coordinates for contract usage
3. **Solidity Format**: Ready-to-use BN254.G1Point struct
4. **KeyRegistrar Format**: Template for key registration (G2 point needed separately)

## Requirements

- Go 1.22+
- The tool will automatically download required dependencies (`golang.org/x/crypto`)

## Constraints

- Scalar must be > 0 and < BN254 field order
- Field order: `0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001`
- Supports both decimal and hexadecimal input (prefix with `0x` for hex)

## Use Cases

- **Testing**: Generate deterministic keys for unit tests
- **Development**: Create keys for local testing without secure enclave
- **Debugging**: Understand BN254 key format and structure
- **Integration**: Get properly formatted keys for EigenLayer contracts

## Security Note

⚠️ **This tool is for development/testing only!** 

For production use, always use the secure enclave script (`key.sh`) which:
- Generates cryptographically secure random scalars
- Runs in hardware-isolated environment
- Never exposes private keys outside the enclave
- Stores keys securely in AWS Secrets Manager
