package main

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"os"
	"strings"

	"golang.org/x/crypto/bn256"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage: %s <scalar_value>\n", os.Args[0])
		os.Exit(1)
	}

	scalarInput := os.Args[1]
	var scalar *big.Int
	var ok bool

	if len(scalarInput) > 2 && scalarInput[:2] == "0x" {
		scalar, ok = new(big.Int).SetString(scalarInput[2:], 16)
	} else {
		scalar, ok = new(big.Int).SetString(scalarInput, 10)
	}

	if !ok {
		fmt.Printf("Invalid scalar: %s\n", scalarInput)
		os.Exit(1)
	}

	fmt.Printf("Testing golang.org/x/crypto/bn256 with scalar %s\n", scalar.String())
	fmt.Println(strings.Repeat("=", 60))

	// Method 1: Use default generator (ScalarBaseMult)
	fmt.Println("\nMethod 1: Default generator (ScalarBaseMult)")
	pubKey1 := new(bn256.G1).ScalarBaseMult(scalar)
	pubKeyBytes1 := pubKey1.Marshal()

	if len(pubKeyBytes1) == 64 {
		x1 := new(big.Int).SetBytes(pubKeyBytes1[0:32])
		y1 := new(big.Int).SetBytes(pubKeyBytes1[32:64])
		fmt.Printf("Result: (%s, %s)\n", x1.String(), y1.String())
	}

	// Method 2: Use standard BN254 generator (1,2) with ScalarMult
	fmt.Println("\nMethod 2: Standard BN254 generator (1,2) with ScalarMult")

	// Create (1,2) point
	coordBytes := make([]byte, 64)
	coordBytes[31] = 1 // X = 1
	coordBytes[63] = 2 // Y = 2

	standardGen, success := new(bn256.G1).Unmarshal(coordBytes)
	if !success {
		fmt.Println("❌ Failed to create (1,2) point")
		return
	}

	fmt.Println("✅ Created standard BN254 generator (1,2)")

	// Now do scalar multiplication: scalar * (1,2)
	pubKey2 := new(bn256.G1).ScalarMult(standardGen, scalar)
	pubKeyBytes2 := pubKey2.Marshal()

	if len(pubKeyBytes2) == 64 {
		x2 := new(big.Int).SetBytes(pubKeyBytes2[0:32])
		y2 := new(big.Int).SetBytes(pubKeyBytes2[32:64])
		fmt.Printf("Result: (%s, %s)\n", x2.String(), y2.String())

		// Check if it's on standard BN254 curve
		p := mustParseBig("21888242871839275222246405745257275088696311157297823662689037894645226208583")
		lhs := new(big.Int).Exp(y2, big.NewInt(2), p)
		rhs := new(big.Int).Add(new(big.Int).Exp(x2, big.NewInt(3), p), big.NewInt(3))
		rhs.Mod(rhs, p)

		if lhs.Cmp(rhs) == 0 {
			fmt.Println("✅ Result is on standard BN254 curve y² = x³ + 3")
		} else {
			fmt.Println("❌ Result is NOT on standard BN254 curve")
		}
	}

	// Compare results
	fmt.Println("\nComparison:")
	if len(pubKeyBytes1) == 64 && len(pubKeyBytes2) == 64 {
		if hex.EncodeToString(pubKeyBytes1) == hex.EncodeToString(pubKeyBytes2) {
			fmt.Println("✅ Both methods produce the SAME result")
		} else {
			fmt.Println("❌ Methods produce DIFFERENT results")
			fmt.Printf("Method 1 hex: %s\n", hex.EncodeToString(pubKeyBytes1))
			fmt.Printf("Method 2 hex: %s\n", hex.EncodeToString(pubKeyBytes2))
		}
	}
}

func mustParseBig(s string) *big.Int {
	n, ok := new(big.Int).SetString(s, 10)
	if !ok {
		panic("failed to parse big int: " + s)
	}
	return n
}
