package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"

	"github.com/consensys/gnark-crypto/ecc/bn254"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
)

// Import the da_keygen functions (assuming they're in the same module)
// Since we can't import from da_key_gen.go due to it being a different package,
// let's copy the essential functions here

func GetG1Generator() *bn254.G1Affine {
	g1Gen := new(bn254.G1Affine)
	_, err := g1Gen.X.SetString("1")
	if err != nil {
		return nil
	}
	_, err = g1Gen.Y.SetString("2")
	if err != nil {
		return nil
	}
	return g1Gen
}

func MulByGeneratorG1(a *fr.Element) *bn254.G1Affine {
	g1Gen := GetG1Generator()
	return new(bn254.G1Affine).ScalarMultiplication(g1Gen, a.BigInt(new(big.Int)))
}

type BN254Key struct {
	Curve   string `json:"curve"`
	PrivHex string `json:"priv_hex"`
	PubHex  string `json:"pub_hex"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage: %s <scalar_value>\n", os.Args[0])
		fmt.Println()
		fmt.Println("Examples:")
		fmt.Println("  go run bn254_keygen_cli.go 12345")
		fmt.Println("  go run bn254_keygen_cli.go 0x1a2b3c4d5e6f")
		fmt.Println("  go run bn254_keygen_cli.go 420")
		fmt.Println("  go run bn254_keygen_cli.go 69")
		fmt.Println()
		fmt.Println("This uses the consensys/gnark-crypto library with EigenLayer-compatible generator (1,2)")
		os.Exit(1)
	}

	scalarInput := os.Args[1]

	// Parse scalar input (supports both decimal and hex)
	var scalar *big.Int
	var ok bool

	if len(scalarInput) > 2 && scalarInput[:2] == "0x" {
		// Hex input
		scalar, ok = new(big.Int).SetString(scalarInput[2:], 16)
		if !ok {
			log.Fatalf("Invalid hex scalar value: %s", scalarInput)
		}
	} else {
		// Decimal input
		scalar, ok = new(big.Int).SetString(scalarInput, 10)
		if !ok {
			log.Fatalf("Invalid decimal scalar value: %s", scalarInput)
		}
	}

	// Create fr.Element from scalar
	var frScalar fr.Element
	frScalar.SetBigInt(scalar)

	// Generate G1 public key using MulByGeneratorG1
	pubKeyG1 := MulByGeneratorG1(&frScalar)

	// Convert to bytes for display
	pubKeyBytes := pubKeyG1.Marshal()

	// Convert scalar to 32-byte representation for consistency
	scalarBytes := make([]byte, 32)
	scalarBytesActual := scalar.Bytes()
	copy(scalarBytes[32-len(scalarBytesActual):], scalarBytesActual)

	// Create the key structure
	key := BN254Key{
		Curve:   "bn254",
		PrivHex: "0x" + hex.EncodeToString(scalarBytes),
		PubHex:  "0x" + hex.EncodeToString(pubKeyBytes),
	}

	// Output the key in JSON format
	keyJSON, err := json.MarshalIndent(key, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal JSON: %v", err)
	}

	fmt.Println("Generated BN254 Key (EigenLayer Compatible):")
	fmt.Println(string(keyJSON))

	// Additional information
	fmt.Printf("\nKey Details:\n")
	fmt.Printf("Private Key (scalar): %s\n", scalar.String())
	fmt.Printf("Private Key (hex): %s\n", key.PrivHex)
	fmt.Printf("Public Key (hex): %s\n", key.PubHex)
	fmt.Printf("Public Key Length: %d bytes\n", len(pubKeyBytes))

	// Get coordinates for comparison
	x := pubKeyG1.X.BigInt(new(big.Int))
	y := pubKeyG1.Y.BigInt(new(big.Int))

	fmt.Printf("\nEigenLayer Public Key Coordinates:\n")
	fmt.Printf("X coordinate: %s\n", x.String())
	fmt.Printf("Y coordinate: %s\n", y.String())
	fmt.Printf("X coordinate (hex): 0x%064x\n", x)
	fmt.Printf("Y coordinate (hex): 0x%064x\n", y)

	// Verify generator for confirmation
	g1Gen := GetG1Generator()
	genX := g1Gen.X.BigInt(new(big.Int))
	genY := g1Gen.Y.BigInt(new(big.Int))
	fmt.Printf("\nGenerator Point (matches Solidity BN254.generatorG1()):\n")
	fmt.Printf("Generator: (%s, %s)\n", genX.String(), genY.String())

	// Format for Solidity/contract usage
	fmt.Printf("\nSolidity Format:\n")
	fmt.Printf("BN254.G1Point memory pubkey = BN254.G1Point({\n")
	fmt.Printf("    X: %s,\n", x.String())
	fmt.Printf("    Y: %s\n", y.String())
	fmt.Printf("});\n")

	// Key data format for KeyRegistrar (needs G2 point too)
	fmt.Printf("\nKeyRegistrar Format (G1 only - G2 point needed separately):\n")
	fmt.Printf("bytes memory keyData = abi.encode(\n")
	fmt.Printf("    %s, // g1X\n", x.String())
	fmt.Printf("    %s, // g1Y\n", y.String())
	fmt.Printf("    [g2X_0, g2X_1], // g2X coordinates\n")
	fmt.Printf("    [g2Y_0, g2Y_1]  // g2Y coordinates\n")
	fmt.Printf(");\n")
}
