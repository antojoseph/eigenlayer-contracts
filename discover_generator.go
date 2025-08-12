package main

import (
	"fmt"
	"math/big"
	"os"
	"strings"

	"github.com/consensys/gnark-crypto/ecc/bn254"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
	"golang.org/x/crypto/bn256"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run discover_generator.go <library>")
		fmt.Println("Libraries: golang | gnark")
		os.Exit(1)
	}

	library := os.Args[1]
	fmt.Printf("Discovering generator point for: %s\n", library)
	fmt.Println(strings.Repeat("=", 50))

	switch library {
	case "golang":
		discoverGolangGenerator()
	case "gnark":
		discoverGnarkGenerator()
	default:
		fmt.Printf("Unknown library: %s\n", library)
		fmt.Println("Available: golang, gnark")
	}
}

func discoverGolangGenerator() {
	fmt.Println("Testing golang.org/x/crypto/bn256...")

	// Method 1: Test with scalar = 1 to get the default generator
	fmt.Println("\n--- Method 1: ScalarBaseMult(1) to find default generator ---")
	scalar1 := big.NewInt(1)
	pubKey1 := new(bn256.G1).ScalarBaseMult(scalar1)
	pubKeyBytes1 := pubKey1.Marshal()

	if len(pubKeyBytes1) == 64 {
		x1 := new(big.Int).SetBytes(pubKeyBytes1[0:32])
		y1 := new(big.Int).SetBytes(pubKeyBytes1[32:64])

		fmt.Printf("Default generator: (%s, %s)\n", x1.String(), y1.String())
		fmt.Printf("Default generator hex: (0x%064x, 0x%064x)\n", x1, y1)
		checkCurveVariants(x1, y1, "golang.org/x/crypto/bn256 (default generator)")
	}

	// Method 2: Start with (1,2) point and do scalar multiplication
	fmt.Println("\n--- Method 2: Start with (1,2) and ScalarMult(1) ---")

	// Try to create a G1 point with (1,2) coordinates
	// Note: This might not work if (1,2) is not on golang's curve
	basePoint := new(bn256.G1)

	// We'll try to unmarshal (1,2) as a point
	coordBytes := make([]byte, 64)
	// X = 1 (32 bytes)
	coordBytes[31] = 1
	// Y = 2 (32 bytes)
	coordBytes[63] = 2

	result, success := basePoint.Unmarshal(coordBytes)
	if !success {
		fmt.Printf("❌ Cannot create (1,2) point in golang library\n")
		fmt.Println("This confirms (1,2) is NOT on golang's curve!")
	} else {
		fmt.Println("✅ Successfully created (1,2) point")

		// Now try scalar multiplication with this point
		scalar2 := big.NewInt(1)
		basePoint = result // Use the successfully unmarshaled point
		scalarResult := new(bn256.G1).ScalarMult(basePoint, scalar2)
		resultBytes := scalarResult.Marshal()

		if len(resultBytes) == 64 {
			x2 := new(big.Int).SetBytes(resultBytes[0:32])
			y2 := new(big.Int).SetBytes(resultBytes[32:64])

			fmt.Printf("(1,2) * 1 = (%s, %s)\n", x2.String(), y2.String())
			checkCurveVariants(x2, y2, "golang.org/x/crypto/bn256 ((1,2) * 1)")
		}
	}

	// Method 3: Let's also try with a different scalar on the default generator
	fmt.Println("\n--- Method 3: Default generator * 2 ---")
	scalar3 := big.NewInt(2)
	pubKey3 := new(bn256.G1).ScalarBaseMult(scalar3)
	pubKeyBytes3 := pubKey3.Marshal()

	if len(pubKeyBytes3) == 64 {
		x3 := new(big.Int).SetBytes(pubKeyBytes3[0:32])
		y3 := new(big.Int).SetBytes(pubKeyBytes3[32:64])

		fmt.Printf("Default generator * 2: (%s, %s)\n", x3.String(), y3.String())
	}
}

func discoverGnarkGenerator() {
	fmt.Println("Testing consensys/gnark-crypto...")

	// Test with scalar = 1
	var scalar fr.Element
	scalar.SetOne()

	// Use the standard generator
	var gen bn254.G1Affine
	gen.X.SetOne()
	gen.Y.SetString("2")

	pubKey := new(bn254.G1Affine).ScalarMultiplication(&gen, scalar.BigInt(new(big.Int)))

	x := pubKey.X.BigInt(new(big.Int))
	y := pubKey.Y.BigInt(new(big.Int))

	fmt.Printf("Generator point: (%s, %s)\n", x.String(), y.String())
	fmt.Printf("Generator hex: (0x%064x, 0x%064x)\n", x, y)

	checkCurveVariants(x, y, "consensys/gnark-crypto")
}

func checkCurveVariants(x, y *big.Int, library string) {
	fmt.Printf("\nCurve equation testing for %s:\n", library)

	// BN254 parameters
	p := mustParseBig("21888242871839275222246405745257275088696311157297823662689037894645226208583")

	curves := map[string]*big.Int{
		"y² = x³ + 3 (standard BN254)": big.NewInt(3),
		"y² = x³ + 0 (secp256k1-like)": big.NewInt(0),
		"y² = x³ + 1":                  big.NewInt(1),
		"y² = x³ + 2":                  big.NewInt(2),
		"y² = x³ + 4":                  big.NewInt(4),
		"y² = x³ + 5":                  big.NewInt(5),
	}

	for desc, b := range curves {
		if isOnCurve(x, y, b, p) {
			fmt.Printf("✅ ON CURVE: %s\n", desc)
		} else {
			fmt.Printf("❌ Not on: %s\n", desc)
		}
	}

	// Check if it's related to (1,2) or (1,-2)
	fmt.Printf("\nRelationship to standard points:\n")

	// Check if it's (1, 2)
	if x.Cmp(big.NewInt(1)) == 0 && y.Cmp(big.NewInt(2)) == 0 {
		fmt.Printf("✅ This IS the point (1, 2)\n")
	}

	// Check if it's (1, -2) ≡ (1, p-2)
	pMinus2 := new(big.Int).Sub(p, big.NewInt(2))
	if x.Cmp(big.NewInt(1)) == 0 && y.Cmp(pMinus2) == 0 {
		fmt.Printf("✅ This IS the point (1, -2) ≡ (1, p-2)\n")
	}

	// Check if there's a simple scalar relationship
	fmt.Printf("\nChecking scalar relationships:\n")
	checkScalarRelation(x, y, big.NewInt(1), big.NewInt(2), p)
	checkScalarRelation(x, y, big.NewInt(1), pMinus2, p)
}

func isOnCurve(x, y, b, p *big.Int) bool {
	// Check if y² ≡ x³ + b (mod p)
	lhs := new(big.Int).Exp(y, big.NewInt(2), p)
	rhs := new(big.Int).Exp(x, big.NewInt(3), p)
	rhs.Add(rhs, b)
	rhs.Mod(rhs, p)
	return lhs.Cmp(rhs) == 0
}

func checkScalarRelation(x1, y1, x2, y2, p *big.Int) {
	// Check if (x1,y1) is a scalar multiple of (x2,y2)
	if x2.Sign() == 0 && y2.Sign() == 0 {
		return // Skip point at infinity
	}

	// For elliptic curves, this is complex, so we'll just check simple cases
	if x1.Cmp(x2) == 0 && y1.Cmp(y2) == 0 {
		fmt.Printf("✅ Point equals (1, 2)\n")
	} else if x1.Cmp(x2) == 0 && y1.Cmp(new(big.Int).Sub(p, y2)) == 0 {
		fmt.Printf("✅ Point is negation of (1, 2) = (1, -2)\n")
	}
}

func mustParseBig(s string) *big.Int {
	n, ok := new(big.Int).SetString(s, 10)
	if !ok {
		panic("failed to parse big int: " + s)
	}
	return n
}
