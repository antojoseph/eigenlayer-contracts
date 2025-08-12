# How to Discover a BN254 Library's Generator Point

Here are several methods to determine what generator point any BN254 library is using:

## Method 1: Test with Scalar = 1 ⭐ **EASIEST**

```go
// For any library, test with privateKey = 1
// Since 1 * generator = generator, you get the generator directly

scalar := big.NewInt(1)
pubKey := library.ScalarMultiply(generator, scalar)
// pubKey coordinates = generator coordinates!
```

**Example:**
```bash
go run extract_bn254_key.go 1
# Output shows: (1, 65000549695646603732796438742359905742825358107623003571877145026864184071781)

go run bn254_keygen_cli.go 1  
# Output shows: (1, 2)
```

## Method 2: Check Library Documentation

Look for:
- `generatorG1()` function
- Constants like `G1_GENERATOR_X`, `G1_GENERATOR_Y`
- README files mentioning generator points

**Example:**
```solidity
// In BN254.sol
function generatorG1() internal pure returns (G1Point memory) {
    return G1Point(1, 2);  // ← Generator is (1, 2)
}
```

## Method 3: Test with Scalar = 2

```go
// Test with scalar = 2
// If generator = (x, y), then 2 * generator = point addition result
scalar := big.NewInt(2)
pubKey := library.ScalarMultiply(generator, scalar)
// More complex but can reveal generator through point addition math
```

## Method 4: Source Code Inspection

Look for:
```go
// Common patterns in Go libraries:
var curveGen = &curvePoint{
    new(big.Int).SetInt64(1),
    new(big.Int).SetInt64(-2),  // ← Generator Y coordinate
    // ...
}

// Or in newer libraries:
func GetG1Generator() *G1Affine {
    g1Gen := new(G1Affine)
    g1Gen.X.SetString("1")
    g1Gen.Y.SetString("2")      // ← Generator Y coordinate
    return g1Gen
}
```

## Method 5: Curve Equation Testing

```python
# Test if the point lies on expected curve
def is_on_curve(x, y, b, p):
    return pow(y, 2, p) == (pow(x, 3, p) + b) % p

# Standard BN254: y² = x³ + 3
p = 21888242871839275222246405745257275088696311157297823662689037894645226208583
print(is_on_curve(1, 2, 3, p))  # Should be True for standard BN254
```

## What We Discovered

| Library | Generator | Curve | EigenLayer Compatible |
|---------|-----------|-------|----------------------|
| `golang.org/x/crypto/bn256` | `(1, unknown)` | **Different curve!** | ❌ **NO** |
| `consensys/gnark-crypto` | `(1, 2)` | `y² = x³ + 3` | ✅ **YES** |
| `EigenLayer/Solidity` | `(1, 2)` | `y² = x³ + 3` | ✅ **Reference** |

## Key Insights

1. **Different Curves**: `golang.org/x/crypto/bn256` uses a completely different curve equation, not just a different generator!

2. **Easy Discovery**: The `scalar = 1` test is the fastest way to see any library's generator

3. **Compatibility**: Only libraries using `(1, 2)` generator on `y² = x³ + 3` curve work with EigenLayer

4. **Historical Context**: The Go library predates modern blockchain standards and uses older curve parameters

## Recommendation

**Always test with scalar = 1** when evaluating a new BN254 library:

```bash
# Quick compatibility test:
your_tool_here 1

# If you get (1, 2) → ✅ EigenLayer compatible
# If you get anything else → ❌ Incompatible
```

This simple test reveals both the generator point and helps verify curve compatibility!
