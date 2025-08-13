# BN254 Key Extraction Tool

## Overview

The `extract_bn254_key.go` tool extracts BN254 cryptographic keys using the same key generation logic as the updated `key.sh` script. It uses the `consensys/gnark-crypto` library for EigenLayer-compatible BN254 key generation.

## Key Features

- **EigenLayer Compatible**: Uses the correct BN254 curve implementation with generator point (1,2)
- **Same Logic as key.sh**: Mirrors the key generation logic from the secure enclave script
- **Original Payload Format**: Outputs keys in the format `{"curve":"bn254","priv_hex":"0x...","pub_hex":"0x..."}`
- **Multiple Output Formats**: Provides key data in JSON, Solidity, and KeyRegistrar formats

## Usage

### Using the wrapper script (recommended):
```bash
./run_extract.sh <scalar_value>
```

### Direct execution:
```bash
# First, set up the correct go.mod
cp go-extract.mod go.mod
cp go-extract.sum go.sum

# Run the tool
go run extract_bn254_key.go <scalar_value>

# Restore original go.mod if needed
```

### Examples:
```bash
# Decimal input
./run_extract.sh 420

# Hexadecimal input
./run_extract.sh 0x1a4

# Generator point (scalar = 1)
./run_extract.sh 1
```

## Technical Details

### Key Generation Process
1. Takes a scalar value (private key) as input
2. Validates the scalar is within the valid BN254 field order
3. Generates G1 public key: `privKey * G1_generator(1,2)`
4. Serializes the public key in compressed format (64 bytes)

### Library Used
- `github.com/consensys/gnark-crypto v0.18.0` - For BN254 elliptic curve operations

### Generator Point
- G1 Generator: `(1, 2)` - The standard BN254 generator point used by EigenLayer

## Output Format

The tool outputs:
1. **JSON Format**: Matching the original `key.sh` payload structure
2. **Key Details**: Scalar value and hex representations
3. **EigenLayer Format**: X and Y coordinates for contract interaction
4. **Solidity Format**: Ready-to-use code for smart contracts
5. **KeyRegistrar Format**: Template for key registration (G2 points needed separately)

## Files

- `extract_bn254_key.go` - The main extraction tool
- `go-extract.mod` - Go module file for the tool
- `go-extract.sum` - Go module checksums
- `run_extract.sh` - Wrapper script for easy execution

## Compatibility

This tool is fully compatible with:
- EigenLayer's BN254 implementation
- The updated `key.sh` script using `consensys/gnark-crypto`
- Smart contracts expecting BN254 G1 points with generator (1,2)
