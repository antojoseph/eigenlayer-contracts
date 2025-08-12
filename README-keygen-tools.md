# BN254 Key Generation Tools

This directory contains tools for generating BN254 cryptographic keys compatible with EigenLayer's smart contracts.

## Problem Solved

Different BN254 libraries use different generator points, causing incompatible key generation:
- **golang.org/x/crypto/bn256**: Uses generator `(1, -2)` 
- **EigenLayer/Solidity**: Uses generator `(1, 2)`
- **consensys/gnark-crypto**: Uses generator `(1, 2)` ✅ Compatible!

## Files

### 1. `bn254_keygen_cli.go` - Main Key Generation Tool

**EigenLayer-compatible** key generation using `consensys/gnark-crypto`.

```bash
# Usage
go run bn254_keygen_cli.go <scalar_value>

# Examples  
go run bn254_keygen_cli.go 420
go run bn254_keygen_cli.go 69
go run bn254_keygen_cli.go 0x1a2b3c4d
```

**Output**: Full key details in multiple formats (JSON, Solidity, KeyRegistrar)

### 2. `da_key_gen.go` - Library Functions

Core BN254 cryptographic functions:
- `MulByGeneratorG1()` - Generate G1 public keys
- `MulByGeneratorG2()` - Generate G2 public keys  
- `VerifySig()` - BLS signature verification
- `CheckG1AndG2DiscreteLogEquality()` - Verify key correspondence
- `GetG1Generator()`, `GetG2Generator()` - Standard generators

### 3. `extract_bn254_key.go` - Legacy Tool (Incompatible)

⚠️ **DO NOT USE for EigenLayer** - Uses wrong generator point.
This tool demonstrates the incompatibility with `golang.org/x/crypto/bn256`.

## Verification

Test that keys match Solidity output:

```bash
# Generate key with CLI
go run bn254_keygen_cli.go 420

# Compare with Solidity
forge script script/deploy/multichain/deploy_globalRootConfirmerSet.s.sol \
  --sig "run(string memory,string memory)" testnet 420 --ffi

# Check generated wallet file
cat script/deploy/multichain/testnet.wallet.json
```

The G1 coordinates should **match exactly**.

## Key Differences

| Tool | Library | Generator | EigenLayer Compatible |
|------|---------|-----------|----------------------|
| `bn254_keygen_cli.go` | `consensys/gnark-crypto` | `(1, 2)` | ✅ Yes |
| `extract_bn254_key.go` | `golang.org/x/crypto/bn256` | `(1, -2)` | ❌ No |
| Solidity BN254 | EVM precompiles | `(1, 2)` | ✅ Reference |

## Example Output

For private key `420`:

**EigenLayer Compatible (correct):**
- X: `14272123054654457709936604042122767711746368495379248511670154852957621272879`
- Y: `5390793356463663377023184148570679692566494850099183968889446432602329490088`

**Incompatible (wrong):**
- X: `53061845057324427919096804943729649108401572077000690831256952915688321874300` 
- Y: `20848940420339237097509758259424604667546386472648135348708409724223698152566`

## Recommendation

**Always use `bn254_keygen_cli.go`** for EigenLayer development to ensure compatibility with the smart contracts and avoid cryptographic mismatches.
