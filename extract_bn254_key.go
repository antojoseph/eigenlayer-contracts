package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"

	"golang.org/x/crypto/bn256"
)

// BN254 field order (same as in the original script)
var rOrder = func() *big.Int {
	v, _ := new(big.Int).SetString("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001", 16)
	return v
}()

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
		fmt.Println("  go run extract_bn254_key.go 12345")
		fmt.Println("  go run extract_bn254_key.go 0x1a2b3c4d5e6f")
		fmt.Println("  go run extract_bn254_key.go 69")
		fmt.Println()
		fmt.Printf("Note: Scalar must be > 0 and < field order (%s)\n", rOrder.String())
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

	// Validate scalar is in valid range for BN254
	if scalar.Sign() <= 0 || scalar.Cmp(rOrder) >= 0 {
		log.Fatalf("Scalar must be > 0 and < field order (%s)", rOrder.String())
	}

	// Convert scalar to 32-byte representation
	scalarBytes := make([]byte, 32)
	scalarBytesActual := scalar.Bytes()
	copy(scalarBytes[32-len(scalarBytesActual):], scalarBytesActual)

	// Generate public key from scalar (same as original script)
	pubKey := new(bn256.G1).ScalarBaseMult(scalar)
	pubKeyBytes := pubKey.Marshal()

	// Create the key structure
	key := BN254Key{
		Curve:   "bn254",
		PrivHex: "0x" + hex.EncodeToString(scalarBytes),
		PubHex:  "0x" + hex.EncodeToString(pubKeyBytes),
	}

	// Output the key in JSON format (same as original script)
	keyJSON, err := json.MarshalIndent(key, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal JSON: %v", err)
	}

	fmt.Println("Generated BN254 Key:")
	fmt.Println(string(keyJSON))

	// Additional information
	fmt.Printf("\nKey Details:\n")
	fmt.Printf("Private Key (scalar): %s\n", scalar.String())
	fmt.Printf("Private Key (hex): %s\n", key.PrivHex)
	fmt.Printf("Public Key (hex): %s\n", key.PubHex)
	fmt.Printf("Public Key Length: %d bytes\n", len(pubKeyBytes))

	// Decode public key coordinates for EigenLayer format
	if len(pubKeyBytes) == 64 {
		x := new(big.Int).SetBytes(pubKeyBytes[0:32])
		y := new(big.Int).SetBytes(pubKeyBytes[32:64])
		fmt.Printf("\nEigenLayer Public Key Format:\n")
		fmt.Printf("X coordinate: %s\n", x.String())
		fmt.Printf("Y coordinate: %s\n", y.String())
		fmt.Printf("X coordinate (hex): 0x%064x\n", x)
		fmt.Printf("Y coordinate (hex): 0x%064x\n", y)

		// Format for Solidity/contract usage
		fmt.Printf("\nSolidity Format (for contracts):\n")
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
}
